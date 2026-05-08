# ==========================================
# МОДУЛЬ: SECURITY & BOT PROTECTION
# ==========================================

_do_ufw_setup() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ufw
    
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    
    for port in "${FINAL_ALLOW_PORTS[@]}"; do
        ufw allow "$port" >/dev/null 2>&1
    done
    
    ufw --force enable >/dev/null 2>&1
}

_do_tg_install() {
    safe_download "https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh" "/tmp/tg_install.sh"
    bash /tmp/tg_install.sh > /dev/null 2>&1
}

_setup_firewalls() {
    draw_header
    echo -e "\n  ${C_INV} [ АНАЛИЗ СЕТИ ] ${C_BASE}\n"
    
    local active_ports=()
    while read -r line; do
        local proto=$(echo "$line" | awk '{print $1}')
        local port=$(echo "$line" | awk '{print $4}' | awk -F':' '{print $NF}')
        if [[ -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
            active_ports+=("$port/$proto")
        fi
    done < <(ss -tulnp | awk 'NR>1' | grep -vE '127\.0\.0\.1|::1' | grep -v 'tcp-ext')
    
    IFS=$'\n' local sorted_active=($(sort -u <<<"${active_ports[*]}")); unset IFS
    
    # Определяем SSH порт
    local default_ssh=$(ss -tlnp 2>/dev/null | grep -w sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
    default_ssh=${default_ssh:-22}

    echo -e "  ${C_DIM}Сейчас сервер слушает следующие порты:${C_BASE}"
    if [ ${#sorted_active[@]} -eq 0 ]; then
        echo -e "  ${C_WHITE}Открытых портов не обнаружено.${C_BASE}\n"
    else
        echo -e "  ${C_WHITE}${sorted_active[*]}${C_BASE}\n"
    fi
    
    cursor_on
    echo -e "  ${C_DIM}Пример ввода: 443/tcp 80/tcp 53/udp${C_BASE}"
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Какие порты оставить открытыми? (SSH ${default_ssh}/tcp защищен от закрытия): ${C_BASE}")" user_ports
    cursor_off
    
    # Автоматически добавляем SSH порт к списку юзера
    user_ports="${default_ssh}/tcp $user_ports"
    
    export FINAL_ALLOW_PORTS=()
    IFS=' ,;' read -r -a p_array <<< "$user_ports"
    for p in "${p_array[@]}"; do
        if [[ "$p" =~ ^[0-9]+$ ]]; then FINAL_ALLOW_PORTS+=("$p/tcp")
        elif [[ "$p" =~ ^[0-9]+/(tcp|udp)$ ]]; then FINAL_ALLOW_PORTS+=("$p")
        fi
    done

    # Убираем дубли на случай, если юзер сам ввел SSH порт руками
    IFS=$'\n' FINAL_ALLOW_PORTS=($(sort -u <<<"${FINAL_ALLOW_PORTS[*]}")); unset IFS

    local will_close=()
    for ap in "${sorted_active[@]}"; do
        local match=0
        for fp in "${FINAL_ALLOW_PORTS[@]}"; do
            if [[ "$ap" == "$fp" ]]; then match=1; break; fi
        done
        if [ $match -eq 0 ]; then will_close+=("$ap"); fi
    done

    echo -e "\n  ${C_DIM}-------------------------------------------------------${C_BASE}"
    echo -e "  ${C_OK}БУДУТ ОТКРЫТЫ:${C_BASE} ${FINAL_ALLOW_PORTS[*]}"
    if [ ${#will_close[@]} -gt 0 ]; then
        echo -e "  ${C_ERR}БУДУТ ЗАКРЫТЫ:${C_BASE} ${will_close[*]}"
    else
        echo -e "  ${C_DIM}Ни один из активных портов не будет закрыт.${C_BASE}"
    fi
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}\n"

    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Подтверждаешь настройку UFW с этими правилами? (y/n): ${C_BASE}")" CONFIRM
    cursor_off
    
    echo ""
    if [[ "$CONFIRM" =~ ^[YyДд] ]]; then
        wait_for_apt
        run_task "Установка и настройка UFW" "_do_ufw_setup"
    else
        echo -e "  ${C_ERR}Пропуск настройки UFW.${C_BASE}\n"
    fi

    if ! check_installed "command -v traffic-guard"; then
        run_task "Установка Traffic-Guard" "_do_tg_install"
    fi
}

step_security() {
    # Обрати внимание на '--- TRAFFIC-GUARD & UFW ---' — это хэдер меню
    local opts=(
        "--- TRAFFIC-GUARD & UFW ---" 
        "Установить UFW и Traffic-Guard" 
        "Остановить Traffic-Guard (Пауза)" 
        "Запустить Traffic-Guard" 
        "Открыть порт (UFW)" 
        "Закрыть порт (UFW)" 
        "Назад"
    )
    while true; do
        render_menu "${opts[@]}"
        clear
        case $MENU_CHOICE in
            1) _setup_firewalls; pause ;;
            2) 
               draw_header
               echo -e "\n  ${C_INV} [ TRAFFIC-GUARD ] ${C_BASE}\n"
               run_task "Остановка сервиса Traffic-Guard" "systemctl stop traffic-guard 2>/dev/null || true"
               pause ;;
            3) 
               draw_header
               echo -e "\n  ${C_INV} [ TRAFFIC-GUARD ] ${C_BASE}\n"
               run_task "Запуск сервиса Traffic-Guard" "systemctl start traffic-guard 2>/dev/null || true"
               pause ;;
            4)
               draw_header
               echo -e "\n  ${C_INV} [ UFW ] ОТКРЫТИЕ ПОРТА ${C_BASE}\n"
               cursor_on
               read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (например, 443 или 80/tcp): ${C_BASE}")" ufw_port
               cursor_off
               echo ""
               if [ -n "$ufw_port" ]; then run_task "Открытие порта $ufw_port" "ufw allow $ufw_port >/dev/null 2>&1"; fi
               pause ;;
            5)
               draw_header
               echo -e "\n  ${C_INV} [ UFW ] ЗАКРЫТИЕ ПОРТА ${C_BASE}\n"
               cursor_on
               read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (например, 443 или 80/tcp): ${C_BASE}")" ufw_port
               cursor_off
               echo ""
               if [ -n "$ufw_port" ]; then run_task "Закрытие порта $ufw_port" "ufw delete allow $ufw_port >/dev/null 2>&1"; fi
               pause ;;
            6) return 0 ;;
        esac
    done
}

_do_bot_ban_logic() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq -o=Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nftables python3 cron

    LIST_URL="https://raw.githubusercontent.com/Loorrr293/blocklist/main/blocklist.txt"
    
    tee /usr/local/sbin/update-blocklist-nft.py > /dev/null <<'PY'
#!/usr/bin/env python3
import sys, ipaddress, urllib.request, json

URL = sys.argv[1]
ASNS = ["AS16265", "AS60781", "AS28753", "AS30633", "AS38731", "AS49367", "AS51395", "AS50673", "AS59253", "AS133752", "AS134351", "AS6939"]

b_v4, b_v6, asn_v4, asn_v6 = [], [], [], []

try:
    req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        for line in r.read().decode('utf-8').splitlines():
            s = line.split('#')[0].strip()
            if not s: continue
            try:
                net = ipaddress.ip_network(s, strict=False)
                if net.version == 4: b_v4.append(net)
                else: b_v6.append(net)
            except ValueError: pass
except Exception: pass

for asn in ASNS:
    try:
        u = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource={asn}"
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read().decode('utf-8'))
            for p in data['data']['prefixes']:
                try:
                    net = ipaddress.ip_network(p['prefix'], strict=False)
                    if net.version == 4: asn_v4.append(net)
                    else: asn_v6.append(net)
                except ValueError: pass
    except Exception: pass

def collapse(nets): return [n.with_prefixlen for n in sorted(ipaddress.collapse_addresses(nets), key=lambda n: n.network_address)]

print("flush set inet aio_filter blocklist_v4")
print("flush set inet aio_filter blocklist_v6")
print("flush set inet aio_filter bad_asn_v4")
print("flush set inet aio_filter bad_asn_v6")

if b_v4: print("add element inet aio_filter blocklist_v4 { " + ", ".join(collapse(b_v4)) + " }")
if b_v6: print("add element inet aio_filter blocklist_v6 { " + ", ".join(collapse(b_v6)) + " }")
if asn_v4: print("add element inet aio_filter bad_asn_v4 { " + ", ".join(collapse(asn_v4)) + " }")
if asn_v6: print("add element inet aio_filter bad_asn_v6 { " + ", ".join(collapse(asn_v6)) + " }")
PY
    chmod +x /usr/local/sbin/update-blocklist-nft.py

    tee /usr/local/sbin/update-blocklist-nft.sh > /dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
nft add table inet aio_filter 2>/dev/null || true
nft add chain inet aio_filter input '{ type filter hook input priority -100; policy accept; }' 2>/dev/null || true

nft add set inet aio_filter blocklist_v4 '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
nft add set inet aio_filter blocklist_v6 '{ type ipv6_addr; flags interval; }' 2>/dev/null || true
nft add set inet aio_filter bad_asn_v4 '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
nft add set inet aio_filter bad_asn_v6 '{ type ipv6_addr; flags interval; }' 2>/dev/null || true

nft list chain inet aio_filter input | grep -q '@blocklist_v4' || nft add rule inet aio_filter input ip saddr @blocklist_v4 drop
nft list chain inet aio_filter input | grep -q '@blocklist_v6' || nft add rule inet aio_filter input ip6 saddr @blocklist_v6 drop
nft list chain inet aio_filter input | grep -q '@bad_asn_v4' || nft add rule inet aio_filter input ip saddr @bad_asn_v4 drop
nft list chain inet aio_filter input | grep -q '@bad_asn_v6' || nft add rule inet aio_filter input ip6 saddr @bad_asn_v6 drop

tmp_rules=$(mktemp)
/usr/local/sbin/update-blocklist-nft.py "$1" > "$tmp_rules"
if [[ -s "$tmp_rules" ]]; then nft -f "$tmp_rules"; fi
rm -f "$tmp_rules"

nft list ruleset > /etc/nftables.conf
systemctl enable nftables >/dev/null 2>&1
SH
    chmod +x /usr/local/sbin/update-blocklist-nft.sh

    tee /etc/systemd/system/blocklist-update.service > /dev/null <<UNIT
[Unit]
Description=Update AIO Blocklist via nftables
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-blocklist-nft.sh ${LIST_URL}
UNIT

    tee /etc/systemd/system/blocklist-update.timer > /dev/null <<'TIMER'
[Timer]
OnBootSec=2min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    systemctl daemon-reload
    systemctl enable --now blocklist-update.timer
    systemctl start blocklist-update.service
    
    systemctl stop ipset-persistent 2>/dev/null || true
    systemctl disable ipset-persistent 2>/dev/null || true
    rm -f /usr/local/bin/block_leaseweb.sh /etc/systemd/system/ipset-persistent.service /etc/ipset.conf
}

step_bot_protection() {
    draw_header
    echo -e "\n  ${C_INV} [ AUTO_NFTABLES & BOT BAN ] ${C_BASE}\n"
    
    if check_installed "[ -f /usr/local/sbin/update-blocklist-nft.py ]"; then return; fi
    wait_for_apt
    run_task "Установка правил nftables и защит" "_do_bot_ban_logic"

    local count_v4=$(nft list set inet aio_filter bad_asn_v4 2>/dev/null | grep -c '/' || echo "0")
    local count_v6=$(nft list set inet aio_filter bad_asn_v6 2>/dev/null | grep -c '/' || echo "0")
    
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}"
    echo -e "  ${C_WHITE}ИТОГ: Забанено ${C_ACCENT}${count_v4}${C_WHITE} IPv4 и ${C_ACCENT}${count_v6}${C_WHITE} IPv6 подсетей хостингов.${C_BASE}"
    
    if ping -c 1 -W 1 85.17.70.38 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Leaseweb НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Leaseweb заблокирован.${C_BASE}"; fi
    
    if ping -c 1 -W 1 74.82.46.6 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Hurricane Electric НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Hurricane Electric заблокирован.${C_BASE}"; fi
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}\n"
}
