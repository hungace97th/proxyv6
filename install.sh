#!/bin/sh

# === CẤU HÌNH TELEGRAM CỦA BẠN ===
TELEGRAM_BOT_TOKEN="9054015301:AAHTLz06YaE15DehbDm9725-mOF0tCpF9ZE"
TELEGRAM_CHAT_ID="hungace97th"

# Tự động cài đặt các gói công cụ còn thiếu trên VPS (Hỗ trợ Ubuntu/Debian/CentOS/AlmaLinux)
echo "Đang kiểm tra và cài đặt các công cụ cần thiết (curl, wget, bsdtar, make, gcc)..."
if [ -f /etc/debian_version ]; then
    apt-get update -y && apt-get install -y wget curl bsdtar make gcc net-tools iptables zip
elif [ -f /etc/redhat-release ]; then
    yum install -y wget curl bsdtar make gcc net-tools iptables zip
fi

random() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c5
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
    URL="https://raw.githubusercontent.com/quayvlog/quayvlog/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    if [ -f "./scripts/rc.d/proxy.sh" ]; then
        cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
        chmod +x /etc/init.d/3proxy
        chkconfig 3proxy on 2>/dev/null || systemctl enable 3proxy 2>/dev/null
    fi
    cd $WORKDIR
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
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' ${WORKDATA})
EOF
}

upload_proxy() {
    PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)
    
    if [ -f "proxy.txt" ]; then
        MESSAGE="🚀 *Tạo IPv6 Proxy Thành Công!*%0A📍 Tổng số lượng: $COUNT%0A🔑 Mật khẩu giải nén zip: \`${PASS}\`%0A🔗 Link tải file zip: ${URL}"
        
        # Gửi tin nhắn text thông báo qua Telegram
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${MESSAGE}" \
            -d "parse_mode=Markdown" >/dev/null

        # Gửi file proxy trực tiếp qua Telegram
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            -F "document=@proxy.txt" \
            -F "caption=Danh sách proxy chi tiết định dạng IP:PORT:USER:PASS" >/dev/null
            
        echo "✅ Đã gửi thông tin và file proxy về Telegram thành công!"
    fi
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random | tr -d '\n')/pass$(random | tr -d '\n')/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
$(awk -F "/" '{print "iptables -A INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5}' ${WORKDATA})
EOF
}

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"
echo "How many proxy do you want to create? Example 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

install_3proxy
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
${WORKDIR}/boot_ifconfig.sh
${WORKDIR}/boot_iptables.sh
ulimit -n 10048
service 3proxy start
EOF

bash ${WORKDIR}/boot_ifconfig.sh
bash ${WORKDIR}/boot_iptables.sh
service 3proxy start 2>/dev/null || /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

gen_proxy_file_for_user
upload_proxy
