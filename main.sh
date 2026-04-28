_do_ufw_setup() {
    export DEBIAN_FRONTEND=noninteractive 
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ufw
    ufw allow "$USER_SSH/tcp"
    ufw allow 3000/tcp
    ufw allow 53/tcp
    ufw allow 53/udp
    echo 'y' | ufw enable
}

_do_tg_install() {
    safe_download "https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh" "/tmp/tg_install.sh" ""
    bash /tmp/tg_install.sh
}

step_security() {
    echo -e "\n${C_ACCENT}[ 08 ] TRAFFIC-GUARD & UFW${C_BASE}\n"
    local default_port=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
    default_port=${default_port:-22}
    
    cursor_on
    echo -e "  ${C_DIM}Настройка файрвола (UFW) может заблокировать доступ к серверу.${C_BASE}"
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Укажи текущий порт SSH [${default_port}]: ${C_BASE}")" USER_SSH
    export USER_SSH=${USER_SSH:-$default_port}
    
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Точно включить UFW и оставить порт ${USER_SSH} открытым? (y/n): ${C_BASE}")" CONFIRM
    cursor_off
    
    if [[ "$CONFIRM" =~ ^[YyДд] ]]; then
        wait_for_apt
        run_task "Установка и настройка UFW" "_do_ufw_setup"
    else
        echo -e "  ${C_ERR}Пропуск настройки UFW.${C_BASE}"
    fi

    if ! check_installed "command -v traffic-guard"; then
        run_task "Установка Traffic-Guard" "_do_tg_install"
    fi
}

_do_bot_ban_logic() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    
    apt-get install -y -qq -o=Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nftables curl python3 ipset iptables-persistent whois ufw
    
    LIST_URL="https://raw.githubusercontent.com/Loorrr293/blocklist/main/blocklist.txt"
    tee /usr/local/sbin/update-blocklist-nft.sh > /dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
URL="${1}"
nft add table inet blocklist 2>/dev/null || true
nft add set inet blocklist v4 '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
nft add set inet blocklist v6 '{ type ipv6_addr; flags interval; }' 2>/dev/null || true
nft add chain inet blocklist input '{ type filter hook input priority raw; policy accept; }' 2>/dev/null || true
nft list chain inet blocklist input | grep -q '@v4' || nft add rule inet blocklist input ip saddr @v4 drop
nft list chain inet blocklist input | grep -q '@v6' || nft add rule inet blocklist input ip6 saddr @v6 drop

tmp="$(mktemp)"; cleaned="$(mktemp)"; v4="$(mktemp)"; v6="$(mktemp)"; nf="$(mktemp)"
trap 'rm -f "$tmp" "$cleaned" "$v4" "$v6" "$nf"' EXIT

curl -fsSL "$URL" > "$tmp"
sed 's/#.*//g' "$tmp" | tr -s ' \t\r' '\n' | sed '/^$/d' | sort -u > "$cleaned"

if [[ ! -s "$cleaned" ]]; then exit 1; fi

python3 - "$cleaned" > "$v4" <<'PY'
import sys, ipaddress
path = sys.argv[1]
nets=[]
for line in open(path,'r',encoding='utf-8',errors='ignore'):
    s=line.strip()
    if not s or ':' in s: continue
    try: nets.append(ipaddress.ip_network(s, strict=False))
    except ValueError: pass
collapsed = sorted(ipaddress.collapse_addresses(nets), key=lambda n:(int(n.network_address), n.prefixlen))
for n in collapsed: print(n.with_prefixlen)
PY

python3 - "$cleaned" > "$v6" <<'PY'
import sys, ipaddress
path = sys.argv[1]
nets=[]
for line in open(path,'r',encoding='utf-8',errors='ignore'):
    s=line.strip()
    if not s or ':' not in s: continue
    try: nets.append(ipaddress.ip_network(s, strict=False))
    except ValueError: pass
collapsed = sorted(ipaddress.collapse_addresses(nets), key=lambda n:(int(n.network_address), n.prefixlen))
for n in collapsed: print(n.with_prefixlen)
PY

{
  echo "flush set inet blocklist v4"
  echo "flush set inet blocklist v6"
  if [[ -s "$v4" ]]; then echo -n "add element inet blocklist v4 { "; paste -sd, "$v4"; echo " }"; fi
  if [[ -s "$v6" ]]; then echo -n "add element inet blocklist v6 { "; paste -sd, "$v6"; echo " }"; fi
} > "$nf"

nft -f "$nf"
SH
    chmod +x /usr/local/sbin/update-blocklist-nft.sh
    tee /etc/systemd/system/blocklist-update.service > /dev/null <<UNIT
[Unit]
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-blocklist-nft.sh ${LIST_URL}
UNIT
    tee /etc/systemd/system/blocklist-update.timer > /dev/null <<'TIMER'
[Timer]
OnBootSec=1min
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
TIMER
    systemctl daemon-reload
    systemctl enable --now blocklist-update.timer
    systemctl start blocklist-update.service

    cat << 'EOF' > /usr/local/bin/block_leaseweb.sh
#!/bin/bash
ASNS=("AS16265" "AS60781" "AS28753" "AS30633" "AS38731" "AS49367" "AS51395" "AS50673" "AS59253" "AS133752" "AS134351" "AS6939")
ipset create leaseweb_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset create leaseweb_v6 hash:net family inet6 hashsize 4096 maxelem 131072 2>/dev/null
ipset create tmp_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset flush tmp_v4
ipset create tmp_v6 hash:net family inet6 hashsize 4096 maxelem 131072 2>/dev/null
ipset flush tmp_v6
for ASN in "${ASNS[@]}"; do
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route:' | awk '{print $2}' | while read -r ip; do ipset add tmp_v4 $ip -quiet; done
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route6:' | awk '{print $2}' | while read -r ip; do ipset add tmp_v6 $ip -quiet; done
done
ipset swap leaseweb_v4 tmp_v4
ipset swap leaseweb_v6 tmp_v6
ipset destroy tmp_v4
ipset destroy tmp_v6
ipset save > /etc/ipset.conf
EOF
    chmod +x /usr/local/bin/block_leaseweb.sh

    cat << 'EOF' > /etc/systemd/system/ipset-persistent.service
[Unit]
Description=Restore ipset sets before iptables
Before=network.target netfilter-persistent.service
ConditionFileNotEmpty=/etc/ipset.conf
[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -file /etc/ipset.conf
ExecStop=/sbin/ipset save -file /etc/ipset.conf
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable ipset-persistent > /dev/null 2>&1
    /usr/local/bin/block_leaseweb.sh
    
    iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m set --match-set leaseweb_v4 dst -j DROP 2>/dev/null || true
    iptables -D FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP 2>/dev/null || true
    ip6tables -D INPUT -m set --match-set leaseweb_v6 src -j DROP 2>/dev/null || true
    ip6tables -D OUTPUT -m set --match-set leaseweb_v6 dst -j DROP 2>/dev/null || true
    ip6tables -D FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP 2>/dev/null || true

    iptables -I INPUT -m set --match-set leaseweb_v4 src -j DROP
    iptables -I OUTPUT -m set --match-set leaseweb_v4 dst -j DROP
    iptables -I FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP

    ip6tables -I INPUT -m set --match-set leaseweb_v6 src -j DROP
    ip6tables -I OUTPUT -m set --match-set leaseweb_v6 dst -j DROP
    ip6tables -I FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP

    netfilter-persistent save > /dev/null 2>&1
    (crontab -l 2>/dev/null | grep -v "block_leaseweb.sh"; echo "0 3 * * 1 /usr/local/bin/block_leaseweb.sh && netfilter-persistent save > /dev/null 2>&1") | crontab -
}

step_bot_protection() {
    echo -e "\n${C_ACCENT}[ 09 ] AUTO_IPTABLES & BOT BAN${C_BASE}\n"
    if check_installed "[ -f /usr/local/bin/block_leaseweb.sh ]"; then return; fi
    wait_for_apt
    run_task "Установка правил iptables и защит" "_do_bot_ban_logic"

    local count_v4=$(ipset list leaseweb_v4 2>/dev/null | grep -c '/' || true)
    local count_v6=$(ipset list leaseweb_v6 2>/dev/null | grep -c '/' || true)
    
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}"
    echo -e "  ${C_WHITE}ИТОГ: Забанено ${C_ACCENT}${count_v4}${C_WHITE} IPv4 и ${C_ACCENT}${count_v6}${C_WHITE} IPv6 подсетей.${C_BASE}"
    
    if ping -c 1 -W 1 85.17.70.38 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Leaseweb НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Leaseweb заблокирован.${C_BASE}"; fi
    
    if ping -c 1 -W 1 74.82.46.6 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Hurricane Electric НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Hurricane Electric заблокирован.${C_BASE}"; fi
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}\n"
}
