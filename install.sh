#!/bin/sh

# === CẤU HÌNH TELEGRAM CỦA BẠN ===
TELEGRAM_BOT_TOKEN="9054015301:AAHTLz06YaE15DehbDm9725-mOF0tCpF9ZE"
TELEGRAM_CHAT_ID="hungace97th"

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
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/hungace97th/proxyv6/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
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
    cat >proxy.txt <<EOF " "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" "/" ":" "Download "Password: "Proxy "Sending "chat_id="${TELEGRAM_CHAT_ID}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" "parse_mode="Markdown" "text="${MESSAGE}" # $(awk $1 $2}' $3 $4 $PASS ${PASS}" ${URL}" ${WORKDATA}) && '\n') '{print --password --upload-file -F -X -d -n -s EOF Format Gửi IP:PORT:LOGIN:PASS" MESSAGE="🚀 *Tạo IPv6 Proxy Thành Công!*\\n📍 Tổng số lượng: $COUNT\\n🔗 Link tải: ${URL}\\n🔑 Mật khẩu zip: \`${PASS}\`" PASS="$(random" POST Telegram Telegram..." URL="$(curl" [ \ ] ]; archive curl echo file from: https://transfer.sh/proxy.zip) if info is proxy proxy.txt proxy.zip ready! then thông tin tiếp to tr trực upload_proxy() và về zip { | }>/dev/null

        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            -F "document=@proxy.txt" \
            -F "caption=File proxy chi tiết (IP:PORT:USER:PASS)" >/dev/null
    fi
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random | tr -d '\n')/pass$(random | tr -d '\n')/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF " "/" "/64"}' "ifconfig "installing "iptables $(awk $4 $5 ${WORKDATA}) '{print --dport --state -F -I -j -m -p -y <<EOF ACCEPT"}' EOF INPUT NEW add apps" bsdtar cat echo eth0 gcc gen_ifconfig() inet6 install net-tools state tcp yum zip { }>/dev/null

install_3proxy

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

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF ${WORKDIR}/boot_ifconfig.sh ${WORKDIR}/boot_iptables.sh -n /etc/rc.local 10048 3proxy EOF ``` bash gen_proxy_file_for_user service start ulimit upload_proxy>
