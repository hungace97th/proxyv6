
#!/bin/bash
set -Eeuo pipefail

# ==========================================
# 3PROXY INSTALLER - CENTOS STREAM 10
# IPv4 IN / IPv6 OUT
# ==========================================

WORKDIR="/home/proxy-installer"
INSTALL_DIR="/usr/local/3proxy"
CONFIG_DIR="/etc/3proxy"
DATA_FILE="$WORKDIR/data.txt"
FIRST_PORT=10000
MAX_PORT=60000

log() {
    echo -e "\n[$(date '+%F %T')] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || fail "Run this script as root."

for cmd in dnf systemctl ip; do
    command -v "$cmd" >/dev/null || fail "Missing command: $cmd"
done

# ==========================================
# INPUT
# ==========================================

read -rp "How many proxies do you want to create? " COUNT

[[ "$COUNT" =~ ^[0-9]+$ ]] || fail "Invalid number."
(( COUNT > 0 && COUNT <= 10000 )) || fail "Count must be 1-10000."

LAST_PORT=$((FIRST_PORT + COUNT - 1))

(( LAST_PORT <= MAX_PORT )) || fail "Port range exceeded."

# ==========================================
# INSTALL PACKAGES
# ==========================================

log "Installing dependencies..."

dnf install -y \
    gcc make git curl zip unzip \
    iproute iputils firewalld \
    openssl python3

systemctl enable --now firewalld

# ==========================================
# DETECT NETWORK
# ==========================================

log "Detecting network..."

IP4=$(curl -4 -fsS --max-time 10 https://icanhazip.com | tr -d '\r\n') \
    || fail "Cannot detect public IPv4."

IP6=$(curl -6 -fsS --max-time 10 https://icanhazip.com | tr -d '\r\n') \
    || fail "Cannot detect public IPv6."

IFACE=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null |
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')

[[ -n "$IFACE" ]] || fail "Cannot detect IPv6 network interface."

# Get the routed /64 prefix.
PREFIX=$(python3 - "$IP6" <<'PY'
import ipaddress, sys
print(ipaddress.IPv6Interface(sys.argv[1] + "/64").network.network_address)
PY
)

PREFIX="${PREFIX%::}"

log "Public IPv4: $IP4"
log "Public IPv6: $IP6"
log "Interface: $IFACE"
log "IPv6 prefix: $PREFIX/64"

# ==========================================
# INSTALL 3PROXY
# ==========================================

log "Downloading official 3proxy source..."

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ ! -d 3proxy-src ]]; then
    git clone --depth 1 \
        https://github.com/3proxy/3proxy.git \
        3proxy-src
fi

cd 3proxy-src

log "Compiling 3proxy..."

make -f Makefile.Linux

BINARY="src/3proxy"

[[ -x "$BINARY" ]] || fail "3proxy binary not found."

mkdir -p "$INSTALL_DIR/bin" "$CONFIG_DIR"

install -m 755 "$BINARY" "$INSTALL_DIR/bin/3proxy"

# ==========================================
# GENERATE PROXY DATA
# ==========================================

log "Generating proxy accounts..."

: > "$DATA_FILE"
: > "$WORKDIR/proxy.txt"

for ((i=0; i<COUNT; i++)); do

    PORT=$((FIRST_PORT + i))

    USERNAME="usr$(openssl rand -hex 5)"
    PASSWORD="pass$(openssl rand -hex 8)"

    # Generate a random IPv6 address within the /64.
    IPV6=$(python3 - "$PREFIX" <<'PY'
import ipaddress, secrets, sys
network = ipaddress.IPv6Network(sys.argv[1] + "::/64")
print(ipaddress.IPv6Address(int(network.network_address) |
                            secrets.randbits(64)))
PY
)

    echo "$USERNAME/$PASSWORD/$PORT/$IPV6" >> "$DATA_FILE"

    echo "$IP4:$PORT:$USERNAME:$PASSWORD" >> "$WORKDIR/proxy.txt"

done

chmod 600 "$DATA_FILE" "$WORKDIR/proxy.txt"

# ==========================================
# IPV6 ADDRESS SETUP
# ==========================================

log "Creating IPv6 setup service..."

cat > "$INSTALL_DIR/add-ipv6.sh" <<EOF
#!/bin/bash
set -e
IFACE="$IFACE"

while IFS=/ read -r USER PASS PORT IPV6; do
    [ -n "\$IPV6" ] || continue
    ip -6 addr replace "\$IPV6/64" dev "\$IFACE" nodad
done < "$DATA_FILE"
EOF

chmod 700 "$INSTALL_DIR/add-ipv6.sh"

cat > /etc/systemd/system/3proxy-ipv6.service <<EOF
[Unit]
Description=Configure 3proxy IPv6 addresses
After=network-online.target
Wants=network-online.target
Before=3proxy.service

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/add-ipv6.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# GENERATE 3PROXY CONFIG
# ==========================================

log "Generating 3proxy configuration..."

cat > "$CONFIG_DIR/3proxy.cfg" <<EOF
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

setgid 65534
setuid 65534

auth strong
EOF

while IFS=/ read -r USER PASS PORT IPV6; do

    [[ -n "$USER" ]] || continue

    cat >> "$CONFIG_DIR/3proxy.cfg" <<EOF

users $USER:CL:$PASS
auth strong
allow $USER
proxy -6 -n -a -p$PORT -i0.0.0.0 -e$IPV6
flush
EOF

done < "$DATA_FILE"

chmod 600 "$CONFIG_DIR/3proxy.cfg"

# ==========================================
# SYSTEMD SERVICE
# ==========================================

log "Creating 3proxy systemd service..."

cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy IPv4 to IPv6 Proxy Server
Requires=3proxy-ipv6.service
After=network-online.target firewalld.service 3proxy-ipv6.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/bin/3proxy $CONFIG_DIR/3proxy.cfg
Restart=on-failure
RestartSec=5
LimitNOFILE=10048

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# FIREWALL
# ==========================================

log "Opening proxy ports..."

firewall-cmd --permanent \
    --add-port="${FIRST_PORT}-${LAST_PORT}/tcp"

firewall-cmd --reload

# ==========================================
# ENABLE AND START
# ==========================================

log "Starting services..."

systemctl daemon-reload

systemctl enable 3proxy-ipv6.service
systemctl enable 3proxy.service

systemctl restart 3proxy-ipv6.service
systemctl restart 3proxy.service

sleep 2

systemctl is-active --quiet 3proxy.service \
    || fail "3proxy failed to start. Check journalctl -u 3proxy."

# ==========================================
# EXPORT PROXY LIST
# ==========================================

log "Exporting proxy list..."

cd "$WORKDIR"

ZIP_PASS=$(openssl rand -hex 8)

zip -q -j -P "$ZIP_PASS" proxy.zip proxy.txt

chmod 600 proxy.zip

# ==========================================
# RESULT
# ==========================================

echo
echo "=========================================="
echo "       3PROXY INSTALLATION COMPLETE"
echo "=========================================="
echo "IPv4       : $IP4"
echo "IPv6 Prefix: $PREFIX/64"
echo "Interface  : $IFACE"
echo "Proxy count: $COUNT"
echo "Port range : $FIRST_PORT - $LAST_PORT"
echo "=========================================="
echo "Proxy list : $WORKDIR/proxy.zip"
echo "ZIP password: $ZIP_PASS"
echo "=========================================="
echo
echo "Check service:"
echo "systemctl status 3proxy"
echo
echo "View logs:"
echo "journalctl -u 3proxy -f"
echo
echo "Proxy format: IP:PORT:LOGIN:PASS"
echo "=========================================="
