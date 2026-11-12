#!/bin/bash
# IPv6 proxy installer (3proxy) - fixed for low-RAM VPS and CentOS/RHEL 9-10 (systemd)

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
FIRST_PORT=10000

if [ "$(id -u)" -ne 0 ]; then
    echo "Hay chay script bang root."
    exit 1
fi

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

setup_swap() {
    # VPS it RAM (<1GB) se bi OOM kill khi dnf chay -> tao swap truoc
    if [ "$(swapon --show --noheadings | wc -l)" -eq 0 ]; then
        echo "Tao swap 1GB de tranh het RAM..."
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
        swapon /swapfile
        grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    fi
}

install_3proxy() {
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/quayvlog/quayvlog/main/3proxy-3proxy-0.8.6.tar.gz"
    cd /tmp || exit 1
    rm -rf 3proxy-3proxy-0.8.6
    wget -qO- "$URL" | tar -xz || { echo "Tai/giai nen 3proxy that bai"; exit 1; }
    cd 3proxy-3proxy-0.8.6 || { echo "Khong thay thu muc 3proxy"; exit 1; }
    make -f Makefile.Linux || { echo "Bien dich 3proxy that bai"; exit 1; }
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/ 2>/dev/null || cp bin/3proxy /usr/local/etc/3proxy/bin/ \
        || { echo "Khong tim thay file binary 3proxy"; exit 1; }
    chmod +x /usr/local/etc/3proxy/bin/3proxy
    cd "$WORKDIR" || exit 1
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_3proxy() {
    cat <<EOF
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA} >"${WORKDIR}/proxy.txt"
}

gen_boot_network() {
    # Script chay moi lan boot: them dia chi IPv6 + mo port firewall
    {
        echo "#!/bin/bash"
        awk -F "/" -v iface="$IFACE" '{print "ip -6 addr add " $5 "/64 dev " iface " 2>/dev/null"}' ${WORKDATA}
        echo "if systemctl is-active --quiet firewalld; then"
        echo "    firewall-cmd --add-port=${FIRST_PORT}-${LAST_PORT}/tcp >/dev/null"
        echo "elif command -v iptables >/dev/null 2>&1; then"
        echo "    iptables -C INPUT -p tcp --dport ${FIRST_PORT}:${LAST_PORT} -j ACCEPT 2>/dev/null || \\"
        echo "    iptables -I INPUT -p tcp --dport ${FIRST_PORT}:${LAST_PORT} -j ACCEPT"
        echo "fi"
    } >"${WORKDIR}/boot_network.sh"
    chmod +x "${WORKDIR}/boot_network.sh"
}

setup_systemd() {
    cat >/etc/systemd/system/proxy-network.service <<EOF
[Unit]
Description=Add IPv6 addresses and open proxy ports
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash ${WORKDIR}/boot_network.sh

[Install]
WantedBy=multi-user.target
EOF

    cat >/etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy IPv6 proxy server
After=network-online.target proxy-network.service
Requires=proxy-network.service

[Service]
Type=simple
LimitNOFILE=10048
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable proxy-network.service 3proxy.service >/dev/null 2>&1
    systemctl restart proxy-network.service
    systemctl restart 3proxy.service
}

# ---------------- main ----------------
mkdir -p "$WORKDIR" && cd "$WORKDIR" || exit 1

setup_swap

echo "installing apps"
dnf -y -q install gcc make tar gzip wget curl zip iproute \
    || { echo "Cai goi that bai, kiem tra lai mang/RAM"; exit 1; }

install_3proxy

echo "working folder = $WORKDIR"

IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

if [ -z "$IFACE" ] || [ -z "$IP4" ] || [ -z "$IP6" ]; then
    echo "Khong lay duoc IFACE/IPv4/IPv6 (IFACE='$IFACE' IP4='$IP4' IP6='$IP6'). Kiem tra VPS da bat IPv6 chua."
    exit 1
fi

echo "Interface = ${IFACE}. Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT
case "$COUNT" in
    ''|*[!0-9]*) echo "Hay nhap mot so nguyen duong"; exit 1 ;;
esac
[ "$COUNT" -lt 1 ] && { echo "So luong phai >= 1"; exit 1; }

LAST_PORT=$((FIRST_PORT + COUNT - 1))

gen_data >"$WORKDATA"
gen_boot_network
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

setup_systemd

gen_proxy_file_for_user

echo
echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
echo "File: ${WORKDIR}/proxy.txt"
echo "Trang thai dich vu: $(systemctl is-active 3proxy.service)"
echo "---- 5 proxy dau tien ----"
head -n 5 "${WORKDIR}/proxy.txt"
