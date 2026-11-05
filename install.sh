
#!/bin/bash

# ============================================================
# 3PROXY IPV6 INSTALLER
# CONVERTED FOR CENTOS STREAM 10
# Original features preserved
# ============================================================

set -Eeuo

# ------------------------------------------------------------
# 1. CHECK ROOT
# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
PROXY_DIR="/usr/local/etc/3proxy"
PROXY_BIN="${PROXY_DIR}/bin/3proxy"
PROXY_CFG="${PROXY_DIR}/3proxy.cfg"

URL="https://raw.githubusercontent.com/hungace97th/proxyv6/main/3proxy-1.0.2.tar.gz"

mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"

# ------------------------------------------------------------
# 2. RANDOM FUNCTIONS
# ------------------------------------------------------------

random() {
    tr </dev/urandom -dc 'A-Za-z0-9' | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }

    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# ------------------------------------------------------------
# 3. INSTALL DEPENDENCIES
# ------------------------------------------------------------

echo "Installing required packages..."

dnf -y install \
    gcc \
    make \
    curl \
    wget \
    tar \
    zip \
    iproute \
    iptables-nft \
    python3 \
    >/dev/null

if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables command not found."
    exit 1
fi

# ------------------------------------------------------------
# 4. DETECT NETWORK INTERFACE
# ------------------------------------------------------------

INTERFACE=$(ip -6 route show default | awk 'NR==1 {print $5}')

if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip route show default | awk 'NR==1 {print $5}')
fi

if [[ -z "$INTERFACE" ]]; then
    echo "Cannot detect network interface."
    exit 1
fi

echo "Network interface = $INTERFACE"

# ------------------------------------------------------------
# 5. DETECT PUBLIC IPV4
# ------------------------------------------------------------

IP4=$(curl -4 -fsS --max-time 15 https://icanhazip.com)

IP4=$(echo "$IP4" | tr -d '[:space:]')

if ! python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$IP4" 2>/dev/null; then
    echo "Cannot detect valid public IPv4."
    exit 1
fi

# ------------------------------------------------------------
# 6. DETECT PUBLIC IPV6 PREFIX AUTOMATICALLY
# ------------------------------------------------------------

echo "Detecting IPv6 prefix..."

PUBLIC_IPV6=$(curl -6 -fsS --max-time 15 https://icanhazip.com)

PUBLIC_IPV6=$(echo "$PUBLIC_IPV6" | tr -d '[:space:]')

IP6=$(python3 - "$PUBLIC_IPV6" <<'PY'
import ipaddress
import sys

try:
    addr = ipaddress.IPv6Address(sys.argv[1])
    if not addr.is_global:
        raise ValueError("IPv6 is not globally routable")

    print(":".join(addr.exploded.split(":")[:4]))

except Exception as e:
    sys.exit(str(e))
PY
)

if [[ -z "$IP6" ]]; then
    echo "Cannot detect IPv6 prefix."
    exit 1
fi

echo "Public IPv4 = $IP4"
echo "External IPv6 prefix = $IP6"

# ------------------------------------------------------------
# 7. INPUT PROXY COUNT
# ------------------------------------------------------------

echo ""
echo "How many proxy do you want to create? Example 500"

read -r COUNT

if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid proxy count."
    exit 1
fi

if (( COUNT > 10000 )); then
    echo "Maximum proxy count is 10000."
    exit 1
fi

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT - 1))

if (( LAST_PORT > 65535 )); then
    echo "Invalid port range."
    exit 1
fi

echo "Creating $COUNT proxies..."
echo "Port range: $FIRST_PORT - $LAST_PORT"

# ------------------------------------------------------------
# 8. INSTALL 3PROXY
# ------------------------------------------------------------

install_3proxy() {

    echo "Installing 3proxy..."

    cd "$WORKDIR"

    rm -rf 3proxy-1.0.2

    curl -fL --retry 3 "$URL" -o 3proxy.tar.gz

    tar -xzf 3proxy.tar.gz

    cd 3proxy-1.0.2

    make -f Makefile.Linux

    if [[ ! -f src/3proxy ]]; then
        echo "3proxy compilation failed."
        exit 1
    fi

    mkdir -p "${PROXY_DIR}"/{bin,logs,stat}

    install -m 755 src/3proxy "$PROXY_BIN"

    cd "$WORKDIR"
}

# ------------------------------------------------------------
# 9. GENERATE PROXY DATA
# ------------------------------------------------------------

gen_data() {

    local port

    for ((port=FIRST_PORT; port<=LAST_PORT; port++)); do

        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 "$IP6")"

    done
}

# ------------------------------------------------------------
# 10. GENERATE 3PROXY CONFIG
# ------------------------------------------------------------

gen_3proxy() {

    cat <<EOF
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

EOF

    awk -F "/" '
    BEGIN {
        printf "users"
    }
    {
        printf " %s:CL:%s", $1, $2
    }
    END {
        printf "\n"
    }
    ' "$WORKDATA"

    awk -F "/" '{
        print "auth strong"
        print "allow " $1
        print "proxy -6 -n -a -p" $4 " -i" $3 " -e" $5
        print "flush"
    }' "$WORKDATA"
}

# ------------------------------------------------------------
# 11. GENERATE PROXY TXT
# ------------------------------------------------------------

gen_proxy_file_for_user() {

    awk -F "/" '{
        print $3 ":" $4 ":" $1 ":" $2
    }' "$WORKDATA" > "${WORKDIR}/proxy.txt"

}

# ------------------------------------------------------------
# 12. GENERATE NETWORK BOOT SCRIPT
# ------------------------------------------------------------

gen_network_boot() {

    cat > "${WORKDIR}/boot_network.sh" <<EOF
#!/bin/bash

set -e

INTERFACE="$INTERFACE"
WORKDATA="$WORKDATA"

# Restore IPv6 addresses
while IFS='/' read -r USER PASS IPV4 PORT IPV6; do

    [[ -z "\$IPV6" ]] && continue

    ip -6 addr replace "\${IPV6}/64" dev "\$INTERFACE"

done < "\$WORKDATA"

# Restore firewall rules
while IFS='/' read -r USER PASS IPV4 PORT IPV6; do

    [[ -z "\$PORT" ]] && continue

    iptables -C INPUT -p tcp --dport "\$PORT" \
        -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp --dport "\$PORT" \
        -m conntrack --ctstate NEW -j ACCEPT

done < "\$WORKDATA"

EOF

    chmod +x "${WORKDIR}/boot_network.sh"
}

# ------------------------------------------------------------
# 13. INSTALL SYSTEMD SERVICES
# ------------------------------------------------------------

install_systemd() {

    # Network and firewall service

    cat > /etc/systemd/system/proxy-boot.service <<EOF
[Unit]
Description=3proxy IPv6 and Firewall Setup
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${WORKDIR}/boot_network.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 3proxy service
    # Run in foreground instead of daemon mode.
    # Systemd manages the process.

    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
Requires=proxy-boot.service
After=network-online.target proxy-boot.service

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=${PROXY_BIN} ${PROXY_CFG}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable proxy-boot.service
    systemctl enable 3proxy.service

}

# ------------------------------------------------------------
# 14. UPLOAD PROXY ZIP
# ------------------------------------------------------------

upload_proxy() {

    local PASS
    local URL

    PASS=$(random)

    cd "$WORKDIR"

    rm -f proxy.zip

    zip -q -P "$PASS" proxy.zip proxy.txt

    chmod 600 proxy.zip

    echo ""
    echo "Uploading proxy.zip to transfer.sh..."

    if URL=$(curl \
        -fsS \
        --retry 2 \
        --connect-timeout 15 \
        --max-time 300 \
        --upload-file proxy.zip \
        https://transfer.sh/proxy.zip); then

        URL=$(echo "$URL" | tr -d '[:space:]')

        if [[ "$URL" == https://transfer.sh/* ]]; then

            echo ""
            echo "Proxy is ready!"
            echo "Format: IP:PORT:LOGIN:PASS"
            echo "Download zip archive from: $URL"
            echo "Password: $PASS"

        else

            echo "Upload response is invalid."
            echo "Local file: ${WORKDIR}/proxy.zip"
            echo "Password: $PASS"

        fi

    else

        echo "Upload failed."
        echo "Local file: ${WORKDIR}/proxy.zip"
        echo "Password: $PASS"

    fi
}

# ============================================================
# MAIN INSTALLATION
# ============================================================

echo "======================================"
echo "       INSTALLING 3PROXY"
echo "======================================"

echo "Working folder = $WORKDIR"

# Generate proxy data

gen_data > "$WORKDATA"

chmod 600 "$WORKDATA"

# Install 3proxy

install_3proxy

# Generate configuration

gen_3proxy > "$PROXY_CFG"

chmod 600 "$PROXY_CFG"

# Generate network boot script

gen_network_boot

# Install systemd

install_systemd

# Start network configuration

echo "Starting IPv6 and firewall configuration..."

systemctl restart proxy-boot.service

# Start 3proxy

echo "Starting 3proxy..."

systemctl restart 3proxy.service

sleep 2

if ! systemctl is-active --quiet 3proxy.service; then

    echo "3proxy failed to start."

    journalctl -u 3proxy.service -n 50 --no-pager

    exit 1

fi

# Generate proxy.txt

gen_proxy_file_for_user

# Upload proxy.zip

upload_proxy

echo ""
echo "======================================"
echo "       INSTALLATION COMPLETED"
echo "======================================"

echo "Public IPv4: $IP4"
echo "IPv6 Prefix: $IP6"
echo "Interface: $INTERFACE"
echo "Total proxies: $COUNT"
echo "Port range: $FIRST_PORT - $LAST_PORT"

echo ""
echo "Proxy TXT: ${WORKDIR}/proxy.txt"
echo "Proxy ZIP: ${WORKDIR}/proxy.zip"

echo ""
echo "Service status:"
systemctl is-active 3proxy.service

echo ""
echo "Check logs:"
echo "journalctl -u 3proxy -f"

echo "======================================"
