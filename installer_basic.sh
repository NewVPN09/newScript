#!/usr/bin/env bash
# Minimal installer: sets up OpenVPN/stunnel/squid/proxy and installs your own scripts if present.
# Ubuntu/Debian only. No MySQL. PAM auth. Menu is linked if you provide a 'menu' file.

set -euo pipefail
GREEN="\033[1;32m"; WHITE="\033[1;37m"; RED="\033[1;31m"; NC="\033[0m"

if [[ $EUID -ne 0 ]]; then echo -e "${RED}Run as root.${NC}"; exit 1; fi

ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime || true

NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
[[ -z "${NIC:-}" ]] && NIC=$(ip -o link show | awk -F': ' '$2 !~ /lo|vir|docker/ {print $2; exit}')
[[ -z "${NIC:-}" ]] && { echo -e "${RED}Cannot detect NIC.${NC}"; exit 1; }
echo -e "${GREEN}NIC:${WHITE} $NIC${NC}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openvpn easy-rsa stunnel4 squid python3 screen iptables-persistent   fail2ban curl net-tools lsof apache2

PLUGIN=""
for p in   /usr/lib/openvpn/openvpn-plugin-auth-pam.so   /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so   /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so   /usr/lib/arm-linux-gnueabihf/openvpn/plugins/openvpn-plugin-auth-pam.so   /usr/lib/aarch64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so
do [[ -f "$p" ]] && PLUGIN="$p" && break; done
[[ -z "$PLUGIN" ]] && { echo -e "${RED}PAM plugin not found.${NC}"; exit 1; }

MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ipv4.icanhazip.com || echo "0.0.0.0")

mkdir -p /etc/openvpn/keys /etc/openvpn/log /etc/openvpn/login /etc/openvpn/script /var/www/html/stat

# Expect you to place ca.crt, server.crt, server.key, dh2048.pem in current dir OR they already exist.
for f in ca.crt server.crt server.key dh2048.pem; do
  if [[ -f "./$f" ]]; then
    install -m 600 "./$f" "/etc/openvpn/keys/$f"
  fi
done

if [[ ! -f /etc/openvpn/keys/ca.crt || ! -f /etc/openvpn/keys/server.crt || ! -f /etc/openvpn/keys/server.key || ! -f /etc/openvpn/keys/dh2048.pem ]]; then
  echo -e "${RED}Missing certificates in /etc/openvpn/keys (ca.crt/server.crt/server.key/dh2048.pem).${NC}"
  echo -e "${WHITE}Place them and re-run.${NC}"; exit 1
fi

cat >/etc/openvpn/server.conf <<EOF
mode server
tls-server
port 1194
proto tcp
dev tun
duplicate-cn
keepalive 10 180
comp-lzo
resolv-retry infinite
max-clients 1000
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server.crt
key /etc/openvpn/keys/server.key
dh /etc/openvpn/keys/dh2048.pem
verify-client-cert none
username-as-common-name
plugin $PLUGIN login
tmp-dir "/etc/openvpn/"
server 172.20.0.0 255.255.0.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "sndbuf 393216"
push "rcvbuf 393216"
tun-mtu 1400
mssfix 1360
verb 3
script-security 2
cipher AES-128-CBC
tcp-nodelay
status /var/log/openvpn-status-tcp.log
log-append /var/log/openvpn-tcp.log
EOF

cat >/etc/openvpn/server1.conf <<EOF
mode server
tls-server
port 110
proto udp
dev tun
duplicate-cn
keepalive 10 180
resolv-retry infinite
max-clients 1000
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server.crt
key /etc/openvpn/keys/server.key
dh /etc/openvpn/keys/dh2048.pem
verify-client-cert none
username-as-common-name
plugin $PLUGIN login
tmp-dir "/etc/openvpn/"
server 172.30.0.0 255.255.0.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "sndbuf 393216"
push "rcvbuf 393216"
tun-mtu 1400
mssfix 1360
verb 3
cipher AES-128-CBC
tcp-nodelay
script-security 2
status /var/log/openvpn-status-udp.log
log-append /var/log/openvpn-udp.log
EOF

# sysctl
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p || true

# iptables
iptables -F; iptables -X; iptables -Z
iptables -t nat -A POSTROUTING -s 172.20.0.0/16 -o "$NIC" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 172.30.0.0/16 -o "$NIC" -j MASQUERADE
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6 || true

# squid
cat >/etc/squid/squid.conf <<EOF
http_port 8080
acl to_vpn dst $(curl -s ipinfo.io/ip || echo $MYIP)
http_access allow to_vpn
via off
forwarded_for off
request_header_access All deny all
http_access deny all
EOF
systemctl enable squid

# stunnel
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 || true
cat >/etc/stunnel/stunnel.conf <<EOF
cert=/etc/stunnel/stunnel.pem
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
client = no
[openvpn]
connect = 127.0.0.1:1194
accept = 443
EOF

# if you have stunnel.pem present, install it
[[ -f ./stunnel.pem ]] && install -m 600 ./stunnel.pem /etc/stunnel/stunnel.pem

# websocket proxy
cat >/usr/local/sbin/proxy.py <<'PYX'
#!/usr/bin/env python3
import socket, threading, select, sys, time
LISTENING_ADDR='0.0.0.0'; LISTENING_PORT=80; BUFLEN=4096*4; TIMEOUT=60
DEFAULT_HOST='127.0.0.1:1194'; RESPONSE=b'HTTP/1.1 101 Switching Protocols \r\n\r\n'
class S(threading.Thread):
  def __init__(self,h,p): super().__init__(); self.h=h; self.p=p
  def run(self):
    s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind((self.h,self.p)); s.listen(0)
    while True:
      c,_=s.accept(); C(c).start()
class C(threading.Thread):
  def __init__(self,c): super().__init__(); self.c=c
  def run(self):
    try:
      _=self.c.recv(BUFLEN)
      t=socket.create_connection(DEFAULT_HOST.split(':'))
      self.c.sendall(RESPONSE); self.fwd(self.c,t)
    except: pass
  def fwd(self,a,b):
    while True:
      r,_,e=select.select([a,b],[],[a,b],3)
      if e: return
      for x in r:
        d=x.recv(BUFLEN)
        if not d: return
        (b if x is a else a).send(d)
S(LISTENING_ADDR,LISTENING_PORT).start()
while True: time.sleep(2)
PYX
chmod +x /usr/local/sbin/proxy.py

cat >/root/auto <<'EOF'
#!/usr/bin/env bash
if ! nc -z localhost 80 >/dev/null 2>&1; then
  screen -dmS proxy2 python3 /usr/local/sbin/proxy.py -p 80
fi
EOF
chmod +x /root/auto
(crontab -l 2>/dev/null | grep -v "/root/auto" || true; echo '* * * * * /bin/bash /root/auto >/dev/null 2>&1') | crontab -

# Apache landing & client
mkdir -p /var/www/html
cat >/var/www/html/index.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>VPN</title></head>
<body style="font-family: monospace; background:#0b0b0b; color:#cfcfcf;">
<div style="max-width:820px;margin:40px auto;">
<h2 style="color:#7CFC00;">VPN Server Ready</h2>
<p>Run <code>menu</code> to manage users (if installed).</p>
</div></body></html>
EOF

cat >/var/www/html/client.ovpn <<EOF
client
dev tun
proto tcp
remote $MYIP 1194
remote-cert-tls server
resolv-retry infinite
nobind
auth-user-pass
cipher AES-128-CBC
verb 3
<ca>
$(cat /etc/openvpn/keys/ca.crt)
</ca>
EOF

# Move Apache to 81
sed -i 's/^Listen 80$/Listen 81/' /etc/apache2/ports.conf || true

# Enable OpenVPN instances
systemctl enable openvpn@server || true
systemctl enable openvpn@server1 || true
systemctl restart openvpn@server || true
systemctl restart openvpn@server1 || true
systemctl restart stunnel4 || true
systemctl restart squid || true
systemctl restart apache2 || true
bash /root/auto || true

# --- Install your own toolset if present in the same dir ---
install_if_exists(){ local f="$1"; if [[ -f "./$f" ]]; then install -m 755 "./$f" "/usr/local/bin/$f"; echo "Installed $f"; fi; }
for f in menu accounts create ram server user_delete user_list; do install_if_exists "$f"; done
# Link menu if provided
if [[ -f /usr/local/bin/menu ]]; then ln -sf /usr/local/bin/menu /usr/bin/menu; echo "Linked 'menu' command."; fi

echo -e "${GREEN}Done.${NC}  Use ${WHITE}menu${NC} (if installed) or add users with:"
echo -e "${WHITE}useradd -s /bin/false -p $(openssl passwd -1 PASS) USER${NC}"
