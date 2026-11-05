#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script bằng quyền root (sudo)."
  exit 1
fi

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"

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

install_3proxy() {
    echo "Đang cài đặt 3proxy..."
    URL="https://raw.githubusercontent.com/hungace97th/proxyv6/main/3proxy-1.0.2.tar.gz"
    wget -qO- "$URL" | bsdtar -xvf-
    cd 3proxy-1.0.2 || exit 1
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    
    # Tạo Systemd service chuẩn cho 3proxy trên CentOS 10
    cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=forking
LimitNOFILE=65535
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable 3proxy.service
    cd "$WORKDIR" || exit 1
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' "${WORKDATA}")

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' "${WORKDATA}")
EOF
}

gen_proxy_file_for_user() {
    cat > proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "${WORKDATA}")
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password "$PASS" proxy.zip proxy.txt >/dev/null
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy đã sẵn sàng! Định dạng IP:PORT:LOGIN:PASS"
    echo "Tải file zip tại: ${URL}"
    echo "Mật khẩu giải nén: ${PASS}"
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read -r port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 "$IP6")"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -J ACCEPT"}' "${WORKDATA}")
EOF
}

gen_ifconfig() {
    # Dùng lệnh ip chuẩn thay vì ifconfig
    cat <<EOF
$(awk -F "/" -v iface="$INTERFACE" '{print "ip -6 addr add " $5 "/64 dev " iface}')
EOF
}

echo "Đang cài đặt các gói phụ thuộc..."
dnf -y install gcc make iproute2 bsdtar zip curl wget >/dev/null

# Tạo thư mục làm việc
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# Tự động phát hiện giao diện mạng chính (Network Interface)
INTERFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | head -n1)
fi
echo "Giao diện mạng đang sử dụng: ${INTERFACE}"

IP4=$(curl -4 -s icanhazip.com || hostname -I | awk '{print $1}')
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP4 = ${IP4}. External IPv6 subnet = ${IP6}"

echo "Bạn muốn tạo bao nhiêu proxy? Ví dụ: 500"
read -r COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

gen_data > "$WORKDATA"
gen_iptables > "${WORKDIR}/boot_iptables.sh"
gen_ifconfig > "${WORKDIR}/boot_ifconfig.sh"
chmod +x "${WORKDIR}"/boot_*.sh

# Cài đặt 3proxy và tạo service
install_3proxy

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

# Tạo Systemd service để tự động chạy các script boot IPv6 và iptables khi khởi động lại
cat <<EOF > /etc/systemd/system/proxy-boot.service
[Unit]
Description=Setup Proxy IPv6 and IPTables Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${WORKDIR}/boot_ifconfig.sh
ExecStart=/bin/bash ${WORKDIR}/boot_iptables.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxy-boot.service
systemctl start proxy-boot.service

# Khởi động dịch vụ 3proxy
systemctl start 3proxy

gen_proxy_file_for_user
upload_proxy