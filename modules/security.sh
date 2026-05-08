# ==============================================================================
# ВИЗУАЛЬНЫЙ ДВИЖОК ДЛЯ МОДУЛЕЙ (Стиль X-UI)
# ==============================================================================
draw_module_header() {
    local title="$1"
    local c_light="\e[38;5;51m"; local c_dark="\e[38;5;24m"; local c_white="\e[38;5;255m"
    local c_gray="\e[38;5;244m"; local c_reset="\e[0m"
    local total_width=37
    local title_len=${#title}
    
    if (( title_len > total_width - 4 )); then title="${title:0:31}.."; title_len=${#title}; fi
    local pad_left=$(( (total_width - title_len) / 2 ))
    local pad_right=$(( total_width - title_len - pad_left ))
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    local sub_text="by •skrım—"
    local sub_len=${#sub_text}
    local sub_pad_left=$(( pad_left + title_len - sub_len ))
    if (( sub_pad_left < 2 || sub_pad_left + sub_len > total_width - 2 )); then sub_pad_left=$(( (total_width - sub_len) / 2 )); fi
    local sub_pad_right=$(( total_width - sub_pad_left - sub_len ))
    local sp_l=$(printf "%${sub_pad_left}s" "")
    local sp_r=$(printf "%${sub_pad_right}s" "")

    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_dark}│${c_reset}${p_l}${c_white}\e[1m${title}${c_reset}${c_light}${p_r}│${c_reset}"
    echo -e "${c_dark}│${c_reset}${sp_l}${c_gray}${sub_text}${c_reset}${c_light}${sp_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}"
}

render_module_menu() {
    local menu_title="$1"; shift; local options=("$@"); local cur=0
    while [[ "${options[$cur]}" == ---* ]]; do ((cur++)); done
    cursor_off; printf "\e[H\e[J"

    while true; do
        printf "\e[H"
        draw_module_header "$menu_title"
        echo -e " ${C_WHITE}[↑↓] Навигация | [Enter] Выбрать${C_BASE}\e[K\n\e[K"

        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" == ---* ]]; then
                local clean_title="${options[$i]#--- }"; clean_title="${clean_title% ---}"
                echo -e "  ${C_DIM}::${C_BASE} ${C_ACCENT}${C_BOLD}${clean_title}${C_BASE} ${C_DIM}::${C_BASE}\e[K"
            elif [ "$i" -eq "$cur" ]; then
                echo -e "  ${C_ACCENT}● [ ${options[$i]} ]${C_BASE}\e[K"
            else
                echo -e "      ${C_WHITE}${options[$i]}${C_BASE}\e[K"
            fi
            if [[ "${options[$i+1]}" == ---* ]]; then echo -e "\e[K"; fi
        done
        printf "\e[J"

        if ! read -rsn3 key; then cursor_on; exit 1; fi
        case "$key" in
            $'\e[A') while true; do ((cur--)); [ "$cur" -lt 0 ] && cur=$((${#options[@]} - 1)); [[ "${options[$cur]}" != ---* ]] && break; done ;;
            $'\e[B') while true; do ((cur++)); [ "$cur" -ge "${#options[@]}" ] && cur=0; [[ "${options[$cur]}" != ---* ]] && break; done ;;
            "") cursor_on; MENU_CHOICE="$cur"; return 0 ;;
        esac
    done
}

_draw_module_progress() {
    local pid=$1
    local width=37; local p=0; local delay=0.1; local ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        local bar=""
        for ((i=0; i<width; i++)); do
            if [ $i -lt $p ]; then bar+="●"; else bar+="○"; fi
        done
        printf "\r\e[?25l  \e[38;5;51m%s\e[0m\e[K" "$bar"
        sleep $delay
        ((ticks++))
        if [ $p -lt $((width * 6 / 10)) ]; then if (( ticks % 2 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width * 8 / 10)) ]; then if (( ticks % 5 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width - 1)) ]; then if (( ticks % 15 == 0 )); then ((p++)); fi
        fi
    done
    printf "\r\e[K"
}

run_module_task() {
    local menu_title="$1"; local task_name="$2"; local cmd_func="$3"
    clear
    draw_module_header "$menu_title"
    echo -e "\n  ${C_ACCENT}${C_BOLD}${task_name}${C_BASE}"
    
    cursor_off
    { eval "$cmd_func"; } >> "$LOG_FILE" 2>&1 &
    local task_pid=$!

    _draw_module_progress "$task_pid" &
    local bar_pid=$!

    wait $task_pid
    local exit_code=$?
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    printf "\r\e[K"
    
    if [ $exit_code -ne 0 ]; then
        echo -e "  ${C_ERR}✗ Ошибка выполнения! Вывод лога:${C_BASE}\n"
        tail -n 12 "$LOG_FILE" | while read -r line; do echo -e "    ${C_DIM}$line${C_BASE}"; done
        echo -e "\n  ${C_WHITE}Полный лог: $LOG_FILE${C_BASE}"
        cursor_on; return 1
    fi
    return 0
}

# ==============================================================================
# МОДУЛЬ: УПРАВЛЕНИЕ IPv6
# ==============================================================================

_do_disable_ipv6() {
    cat <<EON | tee /etc/sysctl.d/99-unswitch-noipv6.conf > /dev/null
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EON
    sysctl --system > /dev/null
}

_do_enable_ipv6() {
    rm -f /etc/sysctl.d/99-unswitch-noipv6.conf 
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null 
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 > /dev/null 
    sysctl --system > /dev/null
}

step_ipv6() {
    local opts=("Отключить IPv6" "Включить IPv6" "Назад")
    while true; do
        render_module_menu "УПРАВЛЕНИЕ IPv6" "${opts[@]}"
        local local_choice=$MENU_CHOICE
        case $local_choice in
            0) run_module_task "УПРАВЛЕНИЕ IPv6" "Отключение протокола IPv6 в ядре..." "_do_disable_ipv6"; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            1) run_module_task "УПРАВЛЕНИЕ IPv6" "Включение протокола IPv6 в ядре..." "_do_enable_ipv6"; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            2) return 0 ;;
        esac
    done
}


# ==============================================================================
# МОДУЛЬ: SECURITY & BOT PROTECTION
# ==============================================================================

_do_ufw_setup() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ufw
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    for port in "${FINAL_ALLOW_PORTS[@]}"; do ufw allow "$port" >/dev/null 2>&1; done
    ufw --force enable >/dev/null 2>&1
}

_do_tg_install() {
    safe_download "https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh" "/tmp/tg_install.sh" ""
    bash /tmp/tg_install.sh > /dev/null 2>&1
}

_setup_firewalls() {
    clear
    draw_module_header "TRAFFIC-GUARD & UFW"
    echo -e "\n  ${C_INV} [ АНАЛИЗ СЕТИ ] ${C_BASE}\n"
    
    local active_ports=()
    # Надежный парсинг портов через ss без заголовков
    while read -r proto addr; do
        local port="${addr##*:}"
        # Пропускаем локалхосты
        if [[ "$addr" == "127.0.0.1:"* ]] || [[ "$addr" == "[::1]:"* ]]; then continue; fi
        if [[ -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
            active_ports+=("$port/$proto")
        fi
    done < <(ss -tulnpH | awk '{print $1, $5}')
    
    IFS=$'\n' local sorted_active=($(sort -u <<<"${active_ports[*]}")); unset IFS
    
    local default_ssh=$(ss -tlnp 2>/dev/null | grep -w sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
    default_ssh=${default_ssh:-22}

    echo -e "  ${C_DIM}Сейчас сервер слушает следующие порты:${C_BASE}"
    if [ ${#sorted_active[@]} -eq 0 ]; then echo -e "  ${C_WHITE}Открытых портов не обнаружено.${C_BASE}\n"
    else echo -e "  ${C_WHITE}${sorted_active[*]}${C_BASE}\n"; fi
    
    cursor_on
    echo -e "  ${C_DIM}Пример ввода: 443/tcp 80/tcp 53/udp${C_BASE}"
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Какие порты оставить открытыми? (SSH ${default_ssh}/tcp защищен): ${C_BASE}")" user_ports
    cursor_off
    
    user_ports="${default_ssh}/tcp $user_ports"
    
    export FINAL_ALLOW_PORTS=()
    IFS=' ,;' read -r -a p_array <<< "$user_ports"
    for p in "${p_array[@]}"; do
        if [[ "$p" =~ ^[0-9]+$ ]]; then FINAL_ALLOW_PORTS+=("$p/tcp")
        elif [[ "$p" =~ ^[0-9]+/(tcp|udp)$ ]]; then FINAL_ALLOW_PORTS+=("$p")
        fi
    done

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
    if [ ${#will_close[@]} -gt 0 ]; then echo -e "  ${C_ERR}БУДУТ ЗАКРЫТЫ:${C_BASE} ${will_close[*]}"
    else echo -e "  ${C_DIM}Ни один из активных портов не будет закрыт.${C_BASE}"; fi
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}\n"

    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Подтверждаешь настройку UFW с этими правилами? (y/n): ${C_BASE}")" CONFIRM
    cursor_off
    
    if [[ "$CONFIRM" =~ ^[YyДд] ]]; then
        run_module_task "TRAFFIC-GUARD & UFW" "Установка и настройка UFW..." "_do_ufw_setup"
    else
        echo -e "\n  ${C_ERR}Пропуск настройки UFW.${C_BASE}"
    fi

    if ! check_installed "command -v traffic-guard"; then
        run_module_task "TRAFFIC-GUARD & UFW" "Установка Traffic-Guard..." "_do_tg_install"
    fi
}

step_security() {
    local opts=(
        "Установить UFW и Traffic-Guard" 
        "Остановить Traffic-Guard (Пауза)" 
        "Запустить Traffic-Guard" 
        "Открыть порт (UFW)" 
        "Закрыть порт (UFW)" 
        "Назад"
    )
    
    while true; do
        render_module_menu "УПРАВЛЕНИЕ ЗАЩИТОЙ" "${opts[@]}"
        case "$MENU_CHOICE" in
            0) _setup_firewalls; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            1) run_module_task "TRAFFIC-GUARD" "Остановка сервиса Traffic-Guard..." "systemctl stop traffic-guard 2>/dev/null || true"; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            2) run_module_task "TRAFFIC-GUARD" "Запуск сервиса Traffic-Guard..." "systemctl start traffic-guard 2>/dev/null || true"; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            3)
                clear; draw_module_header "UFW: ОТКРЫТИЕ ПОРТА"; echo ""
                cursor_on; read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (например, 443 или 80/tcp): ${C_BASE}")" ufw_port; cursor_off
                if [ -n "$ufw_port" ]; then run_module_task "UFW: ОТКРЫТИЕ ПОРТА" "Открытие порта $ufw_port..." "ufw allow $ufw_port >/dev/null 2>&1"; fi
                echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 
                ;;
            4)
                clear; draw_module_header "UFW: ЗАКРЫТИЕ ПОРТА"; echo ""
                cursor_on; read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (например, 443 или 80/tcp): ${C_BASE}")" ufw_port; cursor_off
                if [ -n "$ufw_port" ]; then run_module_task "UFW: ЗАКРЫТИЕ ПОРТА" "Закрытие порта $ufw_port..." "ufw delete allow $ufw_port >/dev/null 2>&1"; fi
                echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 
                ;;
            5) return 0 ;;
        esac
    done
}

_do_bot_ban_logic() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq -o=Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nftables python3

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

print("table inet aio_filter")
print("delete table inet aio_filter")
print("table inet aio_filter {")
if b_v4: print("  set blocklist_v4 { type ipv4_addr; flags interval; elements = { " + ", ".join(collapse(b_v4)) + " } }")
if b_v6: print("  set blocklist_v6 { type ipv6_addr; flags interval; elements = { " + ", ".join(collapse(b_v6)) + " } }")
if asn_v4: print("  set bad_asn_v4 { type ipv4_addr; flags interval; elements = { " + ", ".join(collapse(asn_v4)) + " } }")
if asn_v6: print("  set bad_asn_v6 { type ipv6_addr; flags interval; elements = { " + ", ".join(collapse(asn_v6)) + " } }")
print("  chain input {")
print("    type filter hook input priority -100; policy accept;")
if b_v4: print("    ip saddr @blocklist_v4 drop")
if b_v6: print("    ip6 saddr @blocklist_v6 drop")
if asn_v4: print("    ip saddr @bad_asn_v4 drop")
if asn_v6: print("    ip6 saddr @bad_asn_v6 drop")
print("  }")
print("}")
PY
    chmod +x /usr/local/sbin/update-blocklist-nft.py

    tee /usr/local/sbin/update-blocklist-nft.sh > /dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
tmp_rules=$(mktemp)
/usr/local/sbin/update-blocklist-nft.py "$1" > "$tmp_rules"
if grep -q "elements =" "$tmp_rules"; then nft -f "$tmp_rules"; fi
rm -f "$tmp_rules"
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
    apt-get purge -y -qq iptables-persistent ipset 2>/dev/null || true
    rm -f /usr/local/bin/block_leaseweb.sh /etc/systemd/system/ipset-persistent.service /etc/ipset.conf
}

step_bot_protection() {
    if check_installed "[ -f /usr/local/sbin/update-blocklist-nft.py ]"; then return; fi
    
    run_module_task "AUTO_NFTABLES & BOT BAN" "Установка правил nftables и защит..." "_do_bot_ban_logic"

    local count_v4=$(nft list set inet aio_filter bad_asn_v4 2>/dev/null | grep -c "\." || echo "0")
    local count_v6=$(nft list set inet aio_filter bad_asn_v6 2>/dev/null | grep -c ":" || echo "0")
    
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}"
    echo -e "  ${C_WHITE}ИТОГ: Забанено ${C_ACCENT}${count_v4}${C_WHITE} IPv4 и ${C_ACCENT}${count_v6}${C_WHITE} IPv6 подсетей хостингов.${C_BASE}"
    echo -e "  ${C_WHITE}Включая Leaseweb и Hurricane Electric.${C_BASE}"
    
    if ping -c 1 -W 1 85.17.70.38 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Leaseweb НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Leaseweb заблокирован.${C_BASE}"; fi
    
    if ping -c 1 -W 1 74.82.46.6 > /dev/null 2>&1; then echo -e "  ${C_ERR}ТЕСТ: Hurricane Electric НЕ заблокирован!${C_BASE}"
    else echo -e "  ${C_OK}ТЕСТ: Hurricane Electric заблокирован.${C_BASE}"; fi
    
    echo -e "  ${C_DIM}-------------------------------------------------------${C_BASE}"
    echo -e "  ${C_ACCENT}Огромная благодарность разрабам: Loorrr293 и jaywehosl${C_BASE}\n"
    
    echo -e "${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 
}
