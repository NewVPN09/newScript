#!/bin/bash
set -euo pipefail

# ===== Timezone =====
ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
timedatectl || true

# ===== Packages (NO MySQL or DB deps) =====
apt-get update -y
apt-get install -y openvpn easy-rsa stunnel4 squid apache2 \
  net-tools screen sudo nano fail2ban unzip curl \
  build-essential libwrap0-dev libpam0g-dev libdbus-1-dev \
  libreadline-dev libnl-route-3-dev libpcl1-dev libopts25-dev autogen \
  libgnutls28-dev libseccomp-dev libhttp-parser-dev python3 python3-pip \
  iptables-persistent lsof netcat

# ===== Detect OpenVPN PAM plugin path =====
PLUGIN_PATH=""
for p in \
  /usr/lib/openvpn/openvpn-plugin-auth-pam.so \
  /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so
do
  if [[ -f "$p" ]]; then PLUGIN_PATH="$p"; break; fi
done
if [[ -z "$PLUGIN_PATH" ]]; then
  echo "OpenVPN PAM plugin not found."
  exit 1
fi

# ===== IP & Folders =====
MYIP=$(wget -qO- ipv4.icanhazip.com)
mkdir -p /etc/openvpn/keys /var/www/html/stat
touch /var/www/html/stat/tcp.txt /var/www/html/stat/udp.txt
chmod -R 755 /etc/openvpn

# ===== Certificates/Keys (as provided) =====
read -r -d '' CACERT <<'EOF'
-----BEGIN CERTIFICATE-----
MIIE5TCCA82gAwIBAgIJAP0GLynOqm38MA0GCSqGSIb3DQEBCwUAMIGnMQswCQYD
VQQGEwJQSDERMA8GA1UECBMIQmF0YW5nYXMxETAPBgNVBAcTCEJhdGFuZ2FzMRIw
EAYDVQQKEwlTYXZhZ2VWUE4xEjAQBgNVBAsTCVNhdmFnZVZQTjEWMBQGA1UEAxMN
c2F2YWdlLXZwbi50azEPMA0GA1UEKRMGc2VydmVyMSEwHwYJKoZIhvcNAQkBFhJz
YXZhZ2U5OUBnbWFpbC5jb20wHhcNMTgwNDIwMDQ1MTMyWhcNMjgwNDE3MDQ1MTMy
WjCBpzELMAkGA1UEBhMCUEgxETAPBgNVBAgTCEJhdGFuZ2FzMREwDwYDVQQHEwhC
YXRhbmdhczESMBAGA1UEChMJU2F2YWdlVlBOMRIwEAYDVQQLEwlTYXZhZ2VWUE4x
FjAUBgNVBAMTDXNhdmFnZS12cG4udGsxDzANBgNVBCkTBnNlcnZlcjEhMB8GCSqG
SIb3DQEJARYSc2F2YWdlOTlAZ21haWwuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEAwMNjUVNKJvcMBAx5k/doMtYwVhoSV2gnxA16rtZMnkckHRQc
ApvgSWOBc0e2OgL+rlb48BrheyQ9aSLiHrfGPvzpVQfpGCwSQxayEiNKdRmlb6wl
IIlnhfXyKYXx9x/fZNQWGmhczckrXl84ZYbLKglmnfXSEM0PUlfj7pujjXSsZTPV
2Pe92+sf/2ZyYotA2XXqnXIPjaPUo/kQYqmLTSY7weaYLisxn9TTJo6V0Qap2poY
FLpH7fjWCTun7jZ5CiWVIVARkZRXmurLlu+Z+TMlPK3DW9ASXA2gw8rctsoyLJym
V+6hkZiJ3k0X17SNIDibDG4vn8VFEFehOrqKXQIDAQABo4IBEDCCAQwwHQYDVR0O
BBYEFDC3ZJF7tPbQ9SUDMm6P0hxXmvNIMIHcBgNVHSMEgdQwgdGAFDC3ZJF7tPbQ
9SUDMm6P0hxXmvNIoYGtpIGqMIGnMQswCQYDVQQGEwJQSDERMA8GA1UECBMIQmF0
YW5nYXMxETAPBgNVBAcTCEJhdGFuZ2FzMRIwEAYDVQQKEwlTYXZhZ2VWUE4xEjAQ
BgNVBAsTCVNhdmFnZVZQTjEWMBQGA1UEAxMNc2F2YWdlLXZwbi50azEPMA0GA1UE
KRMGc2VydmVyMSEwHwYJKoZIhvcNAQkBFhJzYXZhZ2U5OUBnbWFpbC5jb22CCQD9
Bi8pzqpt/DAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQCdv9MOSR8O
b9wRw4qd681eTxUYEACFVZpY3eK3vJYyGtblYHIwfCPTWL6yXQxbMud4C1ISIwel
UFv/qnz/GZmAkN0qB5tNSvB48123F1AWfhhXWG+o+xWxUi+eqsXdUVZ1tpP5WQaH
EUtU6SZ1AXO6l6b/RTXymRrEInCPfbGsEnucnG7naOpBaNRXmpiMppOwzR42sd6I
QOvXkj2e8v9tQ05cffjexks+rfb/d80+1nfkv0HCLWxcdU8yOUqVryhdZLB6Rhw/
crldSHwrGWN+qptpFD160iJLIv3p5vWwUAgRoRai9iHuJMOHn4aDX0N8tbCfS+R5
qn8GWiHaXEu8
-----END CERTIFICATE-----
EOF

read -r -d '' SERVERCERT <<'EOF'
-----BEGIN CERTIFICATE-----
MIIFWDCCBECgAwIBAgIBATANBgkqhkiG9w0BAQsFADCBpzELMAkGA1UEBhMCUEgx
ETAPBgNVBAgTCEJhdGFuZ2FzMREwDwYDVQQHEwhCYXRhbmdhczESMBAGA1UEChMJ
U2F2YWdlVlBOMRIwEAYDVQQLEwlTYXZhZ2VWUE4xFjAUBgNVBAMTDXNhdmFnZS12
cG4udGsxDzANBgNVBCkTBnNlcnZlcjEhMB8GCSqGSIb3DQEJARYSc2F2YWdlOTlA
Z21haWwuY29tMB4XDTE4MDQyMDA0NTM0NFoXDTI4MDQxNzA0NTM0NFowgacxCzAJ
BgNVBAYTAlBIMREwDwYDVQQIEwhCYXRhbmdhczERMA8GA1UEBxMIQmF0YW5nYXMx
EjAQBgNVBAoTCVNhdmFnZVZQTjESMBAGA1UECxMJU2F2YWdlVlBOMRYwFAYDVQQD
Ew1zYXZhZ2UtdnBuLnRrMQ8wDQYDVQQpEwZzZXJ2ZXIxITAfBgkqhkiG9w0BCQEW
EnNhdmFnZTk5QGdtYWlsLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
ggEBALapueb5GYUkumvcfrLULAFGJvo+Qe4MuRgnmTQnYetPy4PAC0MnBVOluTxa
isV+LnId+YOXRLUAITbXUSe+t9AMLAk4UqDgiW/LDhE32XxD/rElwS94JcGgFckd
NbYdM+nmdYNLMFSkTvUBrvwMN8DHB0NMBFCAyBOaJ0zRbcaH5Dg4Z8GH5DrjeRHB
I9QscrcMYHLHKX42Fwktyp2zSS8vVoWpJDRa5+tL7s9DuyDv3CaV5t06imHYM7Ao
D/vO2dvdyi+F8OxmWGd3juCgIfi1/uMCfjycXJFlGrw8b849uDiOsNRb76Xhswz0
v0mVex+fQZ/O+q7h52j0+aaZdJUCAwEAAaOCAYswggGHMAkGA1UdEwQCMAAwEQYJ
YIZIAYb4QgEBBAQDAgZAMDQGCWCGSAGG+EIBDQQnFiVFYXN5LVJTQSBHZW5lcmF0
ZWQgU2VydmVyIENlcnRpZmljYXRlMB0GA1UdDgQWBBQMS7N4dcdeyBbSp7yOFT8z
41gZBDCB3AYDVR0jBIHUMIHRgBQwt2SRe7T20PUlAzJuj9IcV5rzSKGBraSBqjCB
pzELMAkGA1UEBhMCUEgxETAPBgNVBAgTCEJhdGFuZ2FzMREwDwYDVQQHEwhCYXRh
bmdhczESMBAGA1UEChMJU2F2YWdlVlBOMRIwEAYDVQQLEwlTYXZhZ2VWUE4xFjAU
BgNVBAMTDXNhdmFnZS12cG4udGsxDzANBgNVBCkTBnNlcnZlcjEhMB8GCSqGSIb3
DQEJARYSc2F2YWdlOTlAZ21haWwuY29tggkA/QYvKc6qbfwwEwYDVR0lBAwwCgYI
KwYBBQUHAwEwCwYDVR0PBAQDAgWgMBEGA1UdEQQKMAiCBnNlcnZlcjANBgkqhkiG
9w0BAQsFAAOCAQEAlROAipVCnha2WF9K0nRh+yUEPHf6CUEF45vfk05ljrgFhzXA
muti+hYNFSh5t3+MVXJ6MRY//7opcAyWeG4eqf9C1/JTQ+bzpDoCe4UYGLy2Vkc7
vq5vHJOLE1UNsVEwwvQDyanPu61gcOwyHuV01U0rXgJzKLCEKPRsk0Wh+DxYkTgh
e7KP/iZMGHKjE3lGuEOMzFwDfCCKUSWL0ICorjNcGSD2qQI5R0IdN8bsn26AW2EL
U78mS221ppgh4K1COn0/yQCjYUx24EU2C35xODdPc6lvv3p3BI0ny+PUEfTDxYXC
HYqfO9pDl43zPjBRtK0rZQRY85V/I7I6+L18+A==
-----END CERTIFICATE-----
EOF

read -r -d '' SERVERKEY <<'EOF'
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC2qbnm+RmFJLpr
3H6y1CwBRib6PkHuDLkYJ5k0J2HrT8uDwAtDJwVTpbk8WorFfi5yHfmDl0S1ACE2
11EnvrfQDCwJOFKg4Ilvyw4RN9l8Q/6xJcEveCXBoBXJHTW2HTPp5nWDSzBUpE71
Aa78DDfAxwdDTARQgMgTmidM0W3Gh+Q4OGfBh+Q643kRwSPULHK3DGByxyl+NhcJ
Lcqds0kvL1aFqSQ0WufrS+7PQ7sg79wmlebdOoph2DOwKA/7ztnb3covhfDsZlhn
d47goCH4tf7jAn48nFyRZRq8PG/OPbg4jrDUW++l4bMM9L9JlXsfn0Gfzvqu4edo
9PmmmXSVAgMBAAECggEAOwhHKDpA4SKpjMpJuAmR3yeI2T7dl81M1F2XyZ8gqiez
ofSiryUhN5NLdhHc306UPBUr2jc84TIVid+0PqAIT5hfcutc6NkoEZUSCsZ95wci
fKWy9WBi81yFLeXewehWKrVsLO5TxEcFrXDJ2HMqYYbw9fLPQiUchBlBsjXMwGgG
W8R2WlQaIh0siJzg+FjwOPEbZA7jAJfyGt80HDWVOfsHxsSX80m8rq2nMppXsngF
hhosj/f/WOPJLiA+/Odkv1ZXS1rqnr5GuwdzrEnibqXOx9LCuxp9MZ8t6qWDvgUf
dy1AB2DKRi9s4NCJHPpITXek4ELawLmGxp7KEzQ/0QKBgQDoU16ZGTCVCT/kQlRz
DRZ2fFXNEvEohCTxYJ72iT6MGxZw+2fuZG6VL9fAgUVLleKKUCFUzM3GPQWEQ1ry
VKQjIqQZjyR+rzdqbHOcG4qYz93enH0FIB9cW/FiU3m5EAzU+TkagZCFq254Kb7i
IQzrWTn24jFX1fQkgcNoXbNUMwKBgQDJRtEs/4e/enVs/6iGjjTGltjyXPS3QM/k
ylZGL+Wc1gQWAsfTO6tYMMPVupyyl2JQjhUydIu3g7D2R4IRKlpprEd8S0MoJou9
Lp/JudlDDJs9Q6Z2q99JpbXdhJ2aOTmSgOKHnkFQRRP/LOxaNwuE/xuhYWubvtFW
y9u+B8uMFwKBgQCJuZqTweYWA+S3aUbs6W5OkUjACKGj9ip8WV4DIrtMjWZRVgh3
v1v63uDVAw1UUKd6fSQ1RDAce+JAVTmd/OVM2uVTLZNh8nc0hNRIT99q1Zdet4A5
wKA2vV6sfnXjaotg2dmrR/Gn/EfBvmWlYhhpkHyXSeIcgv53geGYhiugFwKBgQC3
pRmtyOh+2KjTbuDBBHc6yt/fItlVaplE0yismX8S/mJ0As13+fV4XeYQ2Feoy180
yK6mfpgMNOf9jXkrWE1uJXaD/dekhqbxUd0RHbUR7CqoV1VG6cKtW7j4CMwTryrM
dTQ7MTW+m4iHRuHP3nFwQ6NeN5kLXat7Wj2AwXQCuQKBgESdvXETE6Oy3GVeO1zd
tDlYxpA620daYaNo9MDpV49m89Lt8Maou080+gEJDrqqhyiaEQStrvz31mXIA+w7
YTX1gKAF4qCXy3IKLqN3umdpEYkV2MVEfXlUE6aZZMogta9F5cne3CNDyHzq/RvS
l9rNm+ntgV3+QioNbRWhG9fb
-----END PRIVATE KEY-----
EOF

read -r -d '' DHPARAM <<'EOF'
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEAohzwXz9fsjw+G9Q14qINNOhZnTt/b30zzJYm4o2NIzAngM6E6GPm
N5USUt0grZw6h3VP9LyqQoGi/bHFz33YFG5lgDF8FAASEh07/leF7s0ohhK8pspC
JVD+mRatwBrIImXUpJvYI2pXKxtCOnDa2FFjAOHKixiAXqVcmJRwNaSklQcrpXdn
/09cr0rbFoovn+f1agly4FxYYs7P0XkvSHm3gVW/mhAUr1hvZlbBaWFSVUdgcVOi
FXQ/AVkvxYaO8pFI2Vh+CNMk7Vvi8d3DTayvoL2HTgFi+OIEbiiE/Nzryu+jDGc7
79FkBHWOa/7eD2nFrHScUJcwWiSevPQjQwIBAg==
-----END DH PARAMETERS-----
EOF

echo "$CACERT"     > /etc/openvpn/keys/ca.crt
echo "$SERVERCERT" > /etc/openvpn/keys/server.crt
echo "$SERVERKEY"  > /etc/openvpn/keys/server.key
echo "$DHPARAM"    > /etc/openvpn/keys/dh2048.pem

# ===== PAM service for OpenVPN (system users) =====
cat >/etc/pam.d/openvpn <<'PAM'
# PAM rules for OpenVPN system-user authentication
@include common-auth
@include common-account
PAM

# ===== OpenVPN: TCP 1194 (server.conf) =====
cat >/etc/openvpn/server.conf <<EOF
mode server
tls-server
port 1194
proto tcp
dev tun
duplicate-cn
keepalive 1 180
comp-lzo
resolv-retry infinite
max-clients 1000

ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server.crt
key /etc/openvpn/keys/server.key
dh /etc/openvpn/keys/dh2048.pem

# PAM auth (Linux users)
plugin $PLUGIN_PATH openvpn
verify-client-cert none
username-as-common-name

server 172.20.0.0 255.255.0.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "sndbuf 393216"
push "rcvbuf 393216"
tun-mtu 1400
mssfix 1360
script-security 2
cipher AES-128-CBC
tcp-nodelay
verb 3
EOF

# ===== OpenVPN: UDP 110 (server1.conf) =====
cat >/etc/openvpn/server1.conf <<EOF
mode server
tls-server
port 110
proto udp
dev tun
duplicate-cn
keepalive 1 180
resolv-retry infinite
max-clients 1000

ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server.crt
key /etc/openvpn/keys/server.key
dh /etc/openvpn/keys/dh2048.pem

# PAM auth (Linux users)
plugin $PLUGIN_PATH openvpn
verify-client-cert none
username-as-common-name

server 172.30.0.0 255.255.0.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "sndbuf 393216"
push "rcvbuf 393216"
tun-mtu 1400
mssfix 1360
cipher AES-128-CBC
tcp-nodelay
script-security 2
verb 3
EOF

# ===== Kernel / Sysctl =====
cat >>/etc/sysctl.conf <<'SYS'
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.ipv4.icmp_echo_ignore_all = 1
SYS

echo '* soft nofile 512000
* hard nofile 512000' >> /etc/security/limits.conf
ulimit -n 512000 || true
sysctl -p || true

# ===== iptables (NAT) =====
iptables -F; iptables -X; iptables -Z

for IFACE in enp1s0 eth0 ens3; do
  iptables -t nat -A POSTROUTING -s 172.20.0.0/16 -o "$IFACE" -j MASQUERADE || true
  iptables -t nat -A POSTROUTING -s 172.20.0.0/16 -o "$IFACE" -j SNAT --to-source "$(curl -s ipecho.net/plain)" || true
  iptables -t nat -A POSTROUTING -s 172.30.0.0/16 -o "$IFACE" -j MASQUERADE || true
  iptables -t nat -A POSTROUTING -s 172.30.0.0/16 -o "$IFACE" -j SNAT --to-source "$(curl -s ipecho.net/plain)" || true
done

# Persist iptables
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# ===== Squid (8080) =====
cat >/etc/squid/squid.conf <<EOF
http_port 8080
acl to_vpn dst $(curl -s ipinfo.io/ip)
http_access allow to_vpn
via off
forwarded_for off
request_header_access All deny all
http_access deny all
EOF

# ===== stunnel (443→1194) =====
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

cat >/etc/stunnel/stunnel.pem <<'STPEM'
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAuyrnC0X1e5LsyPVtB0nOj/RPUXJ1jbv+8PcSrAdyvmwq/H3p
eIKEmZ756XMMPKZuS5+FaYV7Qw6lntj0mYwdwO2dzV84XZrFPC/rioSjka9rLsIH
wFK6Zb4rmRbmfEjcoZ22aejbbXlVzScUMRAN3NpvLPcsRH8OPzLR7j5P0CnnBQnS
EKRlwvEqNEqa6qir8DbMnfPh7Lo0V6g15R70ae/VR0MPA5+5Ce0slNt8SQdFmaD5
NL8n+bvkVtJfawfcugdZ5J45rcAc/zBdrtmvmnbVoPLnazDQVkd2u2zfBQtEwZmX
3juAL4Iqb9mh3YIAVqeXVR+pmbcDtHJiKBJxuwIDAQABAoIBAQC3+A6LTSNiaGMn
j9yv2kMXyfqgwtF7E/sdnK0UvGlzdFy4O4bddeSiHtnkNbokby5gVJbMxnAG1IHE
ZdnehxPDy4tdDygXEYamhy+Mwp0IGJVQq1T1HBus38R4wEKijPeYP63J4iC0NRw5
/xxgsTf/ChFW8Ejptr0pL2mbNFI89xRs6Ibgd4MTwLpLi/Pt5dG29iBVXWBBFYkN
wWVDObgR1HevWCOdyQhYIpkfbiMrf5/Kq81pIVT6XR4iYsatLdk2ZGmXoKhskFeh
blMc5DEEQcncQEGlq/mBcDi3o/i7CvXjM/qMuW/mhK16InDYJ3PuMykFmu493d6N
lMmbDdjxAoGBAODa9cDRdXa6jzdwPSWiBpRrxLFXHXLmFHzqzCxZKf5TO5cqUceX
0+AzRS2RG6q4B4yum3wuDyXNNCZCc/TlGIntJCuNwP9rDxZ/pvs6TewXmj4rns4w
59tVhAv4rM+aCxpwZWEFExgqK1sEZKy7EGaqc3jDnA5dzKr5ZTKMDScTAoGBANUX
l04dPzSdQ+x6SsvsfpjAkArVeTLeO0P68qt1D+eQq9XZYiXR//Bog5y4D7g4k2w9
j68CO8wYc+LJUG9ZEa+cVE3TdJPFvA+KSWtQC+rGCGXSUncxFRwyrNwA4fU3dSzZ
GmAm/6tUmbDDpYZzCJF7wUFDZzlTJckf4plFB5e5AoGAEjRoFTZgJj6wfbKOoM9f
bQDUqe79qWHLYtm3shd9+ONQPcrlWB2Iv+wmu6u167p+kftJB2LLQyo8AKT8smUh
+XjDpusRJxzJ2e533Hs599VpXYM2lkcLXoyr5jQ5+YzlPTzAWHyKsTgoznOqmvmC
OG2wb6SWq+sYOPd8I/2GyxUCgYBIh94dXYEdBIaRIFMDND0m+yxMM7ssIE5l5i3h
RFgkhq6mfHaWzvLhvoFFv7TCDKfJSO72L7lwz8XqJIG3VMbbUkezsczVW5GWbIhu
+XEE+WD0X3FoVpGL5ofF3psKn1TH7iG3Jq8RfxtM+lsF93OsKUZvU2T4MyACZFL5
vnBGKQKBgQDZtaNicrnrlu9iP5Eaj0Py2+2MUiP6miB2tARU9yAVQbp3zptjysZG
90eT3stwpNoFz8pidC+TsLvc6+Co941piRoT8zH8ezqxcHvjy2ITTrGOq4tJBPr6
euRNREMSAo3j/2P2kOWK2uHbqkEI2x8epWs/gqAFbuM5Gkk3XfM74g==
-----END RSA PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
MIID8TCCAtmgAwIBAgIJAJtwwttWENtAMA0GCSqGSIb3DQEBCwUAMIGOMQswCQYD
VQQGEwJQaDERMA8GA1UECAwIQmF0YW5nYXMxETAPBgNVBAcMCEJhdGFuZ2FzMQ8w
DQYDVQQKDAZDb2RlUGgxFDASBgNVBAsMC0NvZGVQaCBUZWFtMREwDwYDVQQDDAhK
aG9lIFhpaTEfMB0GCSqGSIb3DQEJARYQY29kZXBoQGdtYWlsLmNvbTAeFw0yMDAz
MTkwOTU3MThaFw0yMzAzMTkwOTU3MThaMIGOMQswCQYDVQQGEwJQaDERMA8GA1UE
CAwIQmF0YW5nYXMxETAPBgNVBAcMCEJhdGFuZ2FzMQ8wDQYDVQQKDAZDb2RlUGgx
FDASBgNVBAsMC0NvZGVQaCBUZWFtMREwDwYDVQQDDAhKaG9lIFhpaTEfMB0GCSqG
SIb3DQEJARYQY29kZXBoQGdtYWlsLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEP
ADCCAQoCggEBALsq5wtF9XuS7Mj1bQdJzo/0T1FydY27/vD3EqwHcr5sKvx96XiC
hJme+elzDDymbkufhWmFe0MOpZ7Y9JmMHcDtnc1fOF2axTwv64qEo5Gvay7CB8BS
umW+K5kW5nxI3KGdtmno2215Vc0nFDEQDdzabyz3LER/Dj8y0e4+T9Ap5wUJ0hCk
ZcLxKjRKmuqoq/A2zJ3z4ey6NFeoNeUe9Gnv1UdDDwOfuQntLJTbfEkHRZmg+TS/
J/m75FbSX2sH3LoHWeSeOa3AHP8wXa7Zr5p21aDy52sw0FZHdrts3wULRMGZl947
gC+CKm/Zod2CAFanl1UfqZm3A7RyYigScbsCAwEAAaNQME4wHQYDVR0OBBYEFHWI
km1tRz5tBz9nZYRK0cR/qm8dMB8GA1UdIwQYMBaAFHWIkm1tRz5tBz9nZYRK0cR/
qm8dMAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAIgxWkM0Y/HF5Cjy
JoLyGkuXwvMKQeBgZ8Pp8eD/5dcRmAETxRwDUROy138IHFXaF8a+UB0cOAzBIiGw
NQt50aU2gx+gasQGuEFqyF8SeBOEKqkjCLMve9heum8fHix2KcD8FDWqXfeuaiFW
uIF6F/1g5+4ZGRWvDD2d3ivh0kRfvCMkWXYp969yBAgVDApuF9PaMPcJiCcWz5a5
hQE5NF7hMpYUagqnr5bryqpcps4j9KkQ+RdM9ZwW9WIDKg3gEBgbKUEAvVjv1bY2
lQ15l8h2WoFxzpP7BTzIic1gLhxh6/YsM2RU6WUPmhUPzUP3xUpx7f+LEdFpuoAs
PYeNUPo=
-----END CERTIFICATE-----
STPEM

cat >/etc/stunnel/stunnel.conf <<'STCONF'
cert=/etc/stunnel/stunnel.pem
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
client = no

[openvpn]
connect = 127.0.0.1:1194
accept = 443
STCONF
chmod 600 /etc/stunnel/stunnel.pem

# ===== Simple Python HTTP proxy on :80 (unchanged logic) =====
cat >/usr/local/sbin/proxy.py <<'PY'
#!/usr/bin/env python3
# Simple TCP tunnel proxy (as provided)
import socket, threading, select, sys, time, getopt

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 80
PASS = ''
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:1194'
RESPONSE = b'HTTP/1.1 101 Switching Protocols \r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__()
        self.running=False; self.host=host; self.port=port
        self.threads=[]; self.threadsLock=threading.Lock()

    def run(self):
        self.soc=socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1)
        self.soc.settimeout(2)
        self.soc.bind((self.host,self.port))
        self.soc.listen(0); self.running=True
        try:
            while self.running:
                try:
                    c, addr = self.soc.accept(); c.setblocking(1)
                except socket.timeout:
                    continue
                conn=ConnectionHandler(c,self,addr); conn.start()
                with self.threadsLock: self.threads.append(conn)
        finally:
            self.running=False; self.soc.close()

    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads: self.threads.remove(conn)

    def close(self):
        self.running=False
        with self.threadsLock:
            for c in list(self.threads): c.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        super().__init__()
        self.clientClosed=False; self.targetClosed=True
        self.client=socClient; self.server=server

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR); self.client.close()
        except: pass
        self.clientClosed=True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR); self.target.close()
        except: pass
        self.targetClosed=True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, b'X-Real-Host') or DEFAULT_HOST
            split = self.findHeader(self.client_buffer, b'X-Split')
            if split: self.client.recv(BUFLEN)
            if hostPort:
                passwd = self.findHeader(self.client_buffer, b'X-Pass')
                if PASS and passwd == PASS.encode():
                    self.method_CONNECT(hostPort)
                elif PASS and passwd != PASS.encode():
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
        except Exception:
            pass
        finally:
            self.close(); self.server.removeConn(self)

    def findHeader(self, head, header):
        try:
            start = head.find(header + b': ')
            if start == -1: return ''
            end = head.find(b'\r\n', start)
            val = head[start:].split(b': ',1)[1][:end - start - len(header) - 2]
            return val.decode()
        except: return ''

    def connect_target(self, host):
        if ':' in host: host, port = host.split(':',1); port = int(port)
        else: port = 80
        self.target = socket.create_connection((host, port))
        self.targetClosed=False

    def method_CONNECT(self, path):
        self.connect_target(path); self.client.sendall(RESPONSE); self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]; count = 0
        while True:
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err: break
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if not data: return
                        if in_ is self.target: self.client.send(data)
                        else:
                            while data:
                                sent = self.target.send(data)
                                data = data[sent:]
                        count = 0
                    except: return
            count += 1
            if count == TIMEOUT: return

def main():
    global LISTENING_ADDR, LISTENING_PORT
    try:
        opts, _ = getopt.getopt(sys.argv[1:],"hb:p:",["bind=","port="])
        for opt,arg in opts:
            if opt in ("-b","--bind"): LISTENING_ADDR = arg
            elif opt in ("-p","--port"): LISTENING_PORT = int(arg)
    except: pass
    print("PythonProxy listening on {}:{}".format(LISTENING_ADDR, LISTENING_PORT))
    server=Server(LISTENING_ADDR, LISTENING_PORT); server.start()
    try:
        while True: time.sleep(2)
    except KeyboardInterrupt:
        server.close()

if __name__ == '__main__': main()
PY
chmod +x /usr/local/sbin/proxy.py

# Auto-restart proxy
cat >/root/auto <<'AUTO'
#!/bin/bash
if nc -z localhost 80; then
  echo "Proxy running"
else
  echo "Starting proxy on 80"
  screen -dmS proxy2 python3 /usr/local/sbin/proxy.py -p 80
fi
AUTO
chmod +x /root/auto
crontab -r || true
echo -e "SHELL=/bin/bash\n* * * * * /bin/bash /root/auto >/dev/null 2>&1" | crontab -

# ===== Client profile (TCP 1194 via direct OpenVPN) =====
cat >/var/www/html/client.ovpn <<EOM
client
dev tun
proto tcp
remote $MYIP 1194
remote-cert-tls server
connect-retry infinite
resolv-retry infinite
nobind
tun-mtu 1500
mssfix 1460
persist-key
persist-tun
auth-user-pass
auth-nocache
script-security 2
cipher AES-128-CBC
keysize 0
setenv CLIENT_CERT 0
reneg-sec 0
verb 3
<ca>
$CACERT
</ca>
EOM

# ===== Simple landing page =====
cat >/var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>KALDAG VPN</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://bootswatch.com/4/slate/bootstrap.min.css">
</head>
<body>
<div class="container" style="padding-top: 50px">
  <div class="jumbotron text-center">
    <h1 class="display-4">KALDAG VPN</h1>
    <p class="lead">Plain installer • System-user login • No database</p>
    <hr>
    <p><a class="btn btn-primary btn-lg" href="/client.ovpn" role="button">Download client.ovpn</a></p>
  </div>
</div>
</body>
</html>
HTML

# Move Apache HTTP to 81 (proxy uses 80)
sed -i 's/Listen 80/Listen 81/g' /etc/apache2/ports.conf

# ===== Enable & start services =====
update-rc.d stunnel4 enable
update-rc.d openvpn enable
update-rc.d apache2 enable

systemctl restart squid || service squid restart
systemctl restart stunnel4 || service stunnel4 restart
systemctl restart openvpn || service openvpn restart
systemctl restart apache2 || service apache2 restart

# Clean up
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true

echo "============================================"
echo " Install complete."
echo " OpenVPN TCP: $MYIP:1194"
echo " OpenVPN UDP: $MYIP:110"
echo " stunnel    : $MYIP:443 -> 127.0.0.1:1194"
echo " Squid      : $MYIP:8080"
echo " Proxy      : $MYIP:80 (kept for compatibility)"
echo " Web (OVPN) : http://$MYIP:81/client.ovpn"
echo "--------------------------------------------"
echo " Add users with:"
echo "   sudo useradd -s /bin/false -p \$(openssl passwd -1 PASS) USER"
echo " Then connect with USER / PASS in your OpenVPN client."
echo "============================================"
