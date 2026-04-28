#!/bin/bash

export SCRIPT_VERSION="2.0"
export INSTALL_DIR="/opt/aio_gentle"
export LOG_FILE="/var/log/aio_setup.log"

if [[ $EUID -ne 0 ]]; then
   echo -e "\e[1;31mОшибка: Скрипт должен быть запущен от имени root.\e[0m"
   exit 1
fi

echo -e "\n========================================" >> "$LOG_FILE"
echo "Запуск AIO VPN GENTLE UTILITY: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

export C_BASE='\e[0m'
export C_ACCENT='\e[1;36m' 
export C_DIM='\e[90m'      
export C_OK='\e[32m'       
export C_ERR='\e[31m'      
export C_INV='\e[7m'       
export C_WHITE='\e[97m'    
export C_BOLD='\e[1m'

cursor_off() { printf "\e[?25l"; }
cursor_on()  { printf "\e[?25h"; }
trap "cursor_on; echo; exit" SIGINT

draw_header() {
    local title="$1"
    local width=54
    local title_len=${#title}
    local pad_right=$(( width - 2 - title_len ))
    [[ $pad_right -lt 0 ]] && pad_right=0
    local pad_spaces=$(printf "%${pad_right}s" "")
    
    echo -e "${C_ACCENT}┌──────────────────────────────────────────────────────┐${C_BASE}\e[K"
    echo -e "${C_ACCENT}│  ${title}${pad_spaces}│${C_BASE}\e[K"
    echo -e "${C_ACCENT}└──────────────────────────────────────────────────────┘${C_BASE}\e[K"
}

_draw_progress() {
    local pid=$1
    local width=15; local p=0; local delay=0.1; local ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        local bar="["
        for ((i=0; i<width; i++)); do
            if [ $i -lt $p ]; then bar+="■"; else bar+="·"; fi
        done
        bar+="]"
        printf "\e[u%b%s%b" "$C_ACCENT" "$bar" "$C_BASE"
        sleep $delay
        ((ticks++))
        if [ $p -lt $((width * 6 / 10)) ]; then
            if (( ticks % 2 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width * 8 / 10)) ]; then
            if (( ticks % 5 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width - 1)) ]; then
            if (( ticks % 15 == 0 )); then ((p++)); fi
        fi
    done
}

run_task() {
    local task_name=$1
    local cmd_func=$2
    cursor_off
    local text_len=${#task_name}
    local pad_len=$(( 50 - text_len ))
    [[ $pad_len -lt 1 ]] && pad_len=1
    local pad_spaces=$(printf "%${pad_len}s" "")
    printf "  ${C_ACCENT}${C_BOLD}%s%s${C_BASE}" "$task_name" "$pad_spaces"
    printf "\e[s"

    $cmd_func >> "$LOG_FILE" 2>&1 &
    local task_pid=$!

    _draw_progress "$task_pid" &
    local bar_pid=$!

    wait $task_pid
    local exit_code=$?
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    printf "\e[u\e[K"

    if [ $exit_code -eq 0 ]; then
        echo -e "${C_OK}✓${C_BASE}"
    else
        echo -e "${C_ERR}[ОШИБКА]${C_BASE}"
        echo -e "  ${C_WHITE}Смотри логи: $LOG_FILE${C_BASE}"
        cursor_on; exit 1
    fi
}

safe_download() {
    local url="$1" dest="$2" expected_hash="$3"
    curl -sSL "$url" > "$dest"
    if [ -n "$expected_hash" ]; then
        if [ "$(sha256sum "$dest" | awk '{print $1}')" != "$expected_hash" ]; then
            rm -f "$dest"; return 1
        fi
    fi
    return 0
}

check_installed() {
    if eval "$1" >/dev/null 2>&1; then
        echo -e "\n  ${C_OK}[ ИНФО ]${C_BASE} Компонент уже установлен."
        return 0
    else
        return 1
    fi
}

wait_for_apt() {
    while apt-get check 2>&1 | grep -q "lock"; do sleep 5; done
}

export MENU_CHOICE=""
render_menu() {
    local title="$1"
    shift
    local options=("$@")
    local cur=0
    while [[ "${options[$cur]}" == ---* ]]; do ((cur++)); done
    cursor_off
    printf "\e[H\e[J"

    while true; do
        printf "\e[H"
        draw_header "$title"
        echo -e "${C_WHITE} [↑↓] Навигация | [Enter] Выбрать | Алиас: ${C_ACCENT}aio_gentle${C_BASE}\e[K\n\e[K"

        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" == ---* ]]; then
                echo -e "\n  ${C_ACCENT}${C_BOLD}${options[$i]}${C_BASE}\e[K"
            elif [ "$i" -eq "$cur" ]; then
                echo -e "${C_ACCENT}  > ${C_INV} ${options[$i]} ${C_BASE}\e[K"
            else
                echo -e "      ${options[$i]}\e[K"
            fi
        done
        printf "\e[J"

        # Защита от EOF 
        if ! read -rsn3 key; then
            cursor_on
            echo -e "\n\e[31m[ ОШИБКА ] Потеряна связь с терминалом. Запусти утилиту вручную: aio_gentle\e[0m"
            exit 1
        fi

        case "$key" in
            $'\e[A') while true; do ((cur--)); [ "$cur" -lt 0 ] && cur=$((${#options[@]} - 1)); [[ "${options[$cur]}" != ---* ]] && break; done ;;
            $'\e[B') while true; do ((cur++)); [ "$cur" -ge "${#options[@]}" ] && cur=0; [[ "${options[$cur]}" != ---* ]] && break; done ;;
            "") cursor_on; MENU_CHOICE="$cur"; return 0 ;;
        esac
    done
}

# Подгрузка модулей
for f in "$INSTALL_DIR"/modules/*.sh; do source "$f"; done

step_update_script() {
    echo -e "\n${C_ACCENT}[ ОБНОВЛЕНИЕ СКРИПТА ]${C_BASE}\n"
    cd "$INSTALL_DIR" || exit
    echo -e "  ${C_DIM}Синхронизация с GitHub...${C_BASE}"
    git pull origin main >/dev/null 2>&1
    echo -e "\n  ${C_OK}Скрипт успешно обновлен! Перезапуск...${C_BASE}"
    sleep 1
    exec /usr/local/bin/aio_gentle
}

step_uninstall_script() {
    echo -e "\n${C_ACCENT}[ УДАЛЕНИЕ СКРИПТА ]${C_BASE}\n"
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Точно удалить утилиту? (y/n): ${C_BASE}")" CONFIRM
    cursor_off
    if [[ ! "$CONFIRM" =~ ^[YyДд] ]]; then return 1; fi
    rm -rf "$INSTALL_DIR" /usr/local/bin/aio_gentle /var/log/aio_setup.log
    echo -e "  ${C_OK}Удалено! До встречи!${C_BASE}\n"
    cursor_on; exit 0
}

options=(
    "--- ПАНЕЛИ И ПРОКСИ ---"
    "3x-ui"
    "--- БАЗОВЫЕ НАСТРОЙКИ ---"
    "Базовая подготовка" 
    "Ядро XanMod" 
    "BBR & TCP" 
    "Swap (Подкачка)"
    "--- СЕТЬ И ЗАЩИТА ---"
    "Управление IPv6"
    "Traffic-Guard & UFW" 
    "Auto_IPtables & Bot Ban" 
    "Управление SSL сертификатами"
    "--- СЕРВИСЫ ---"
    "Управление Docker"
    "Управление AdGuard Home" 
    "Управление Beszel" 
    "Управление WARP" 
    "--- ИНФОРМАЦИЯ ---"
    "Speedtest (Ookla)"
    "IP Region Check"
    "Очистка и ротация логов"
    "--- УПРАВЛЕНИЕ СКРИПТОМ ---"
    "Обновить скрипт"
    "Удалить скрипт"
    "Обойти белые списки"
    "Выход"
)

while read -r -t 0.1 -n 10000; do :; done

while true; do
    render_menu "AIO VPN GENTLE UTILITY v${SCRIPT_VERSION}" "${options[@]}"
    choice=$MENU_CHOICE
    NEEDS_PAUSE=1
    
    clear
    case "${options[$choice]}" in
        "3x-ui") step_3x_ui || NEEDS_PAUSE=0 ;;
        "Базовая подготовка") step_prepare ;;
        "Ядро XanMod") step_kernel ;;
        "BBR & TCP") step_network ;;
        "Swap (Подкачка)") step_swap || NEEDS_PAUSE=0 ;;
        "Управление IPv6") step_ipv6 || NEEDS_PAUSE=0 ;;
        "Traffic-Guard & UFW") step_security ;;
        "Auto_IPtables & Bot Ban") step_bot_protection ;;
        "Управление SSL сертификатами") step_letsencrypt || NEEDS_PAUSE=0 ;;
        "Управление Docker") step_docker || NEEDS_PAUSE=0 ;;
        "Управление AdGuard Home") step_adguard || NEEDS_PAUSE=0 ;;
        "Управление Beszel") step_beszel || NEEDS_PAUSE=0 ;;
        "Управление WARP") step_warp || NEEDS_PAUSE=0 ;;
        "Speedtest (Ookla)") step_speedtest ;;
        "IP Region Check") step_ipregion ;;
        "Очистка и ротация логов") step_logs ;;
        "Обновить скрипт") step_update_script ;;
        "Удалить скрипт") step_uninstall_script || NEEDS_PAUSE=0 ;;
        "Обойти белые списки") step_bypass_whitelist ;;
        "Выход") cursor_on; exit 0 ;;
    esac
    
    if [ "$NEEDS_PAUSE" -eq 1 ]; then
        echo -e "\n${C_OK}Нажми любую клавишу для возврата в меню...${C_BASE}"
        read -rsn1
    fi
done
