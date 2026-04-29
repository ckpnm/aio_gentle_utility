#!/bin/bash

export SCRIPT_VERSION="1.05"
export GITHUB_URL="https://github.com/ckpnm/aio_gentle"
export UPDATE_NEEDED=0

# Реальный путь к main.sh, даже если он запущен через симлинк
export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}")")" &> /dev/null && pwd)"
export MODULES_DIR="$SCRIPT_DIR/modules"
export LOG_FILE="/var/log/aio_setup.log"

if [[ $EUID -ne 0 ]]; then
   echo -e "\e[1;31mОшибка: Скрипт должен быть запущен от имени root.\e[0m"
   exit 1
fi

echo -e "\n========================================" >> "$LOG_FILE"
echo "Запуск AIO VPN GENTLE UTILITY: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# ==========================================
# ВИЗУАЛ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ==========================================
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

pause() {
    cursor_off
    echo -e "\n${C_OK}Нажми любую клавишу для возврата в меню...${C_BASE}"
    read -rsn1
}

check_updates() {
    local remote_version
    
    remote_version=$(curl -s --max-time 3 "https://raw.githubusercontent.com/ckpnm/aio_gentle/main/main.sh?t=$RANDOM" | grep -E '^export SCRIPT_VERSION=' | awk -F'=' '{print $2}' | tr -d '"'\''')
    
    if [[ -n "$remote_version" && "$remote_version" != "$SCRIPT_VERSION" ]]; then
        UPDATE_NEEDED=1
        export REMOTE_VERSION="$remote_version"
    fi
}

draw_header() {
    # Цветовая палитра
    local c_light="\e[38;5;51m"   # Яркий циан
    local c_dark="\e[38;5;24m"    # Темный циан
    local c_white="\e[38;5;255m"  # Белый
    local c_gray="\e[38;5;244m"   # Серый
    local c_red="\e[38;5;196m"    # Красный
    local c_reset="\e[0m"         # Сброс

    local ver_color="$c_white"
    [[ "$UPDATE_NEEDED" -eq 1 ]] && ver_color="$c_red"

    # Высчитываем пробелы, чтобы текст всегда был по центру рамки
    local total_width=37
    local title_text="A I O - G E N T L E v"
    local title_len=$(( ${#title_text} + ${#SCRIPT_VERSION} ))
    local pad_left=$(( (total_width - title_len) / 2 ))
    local pad_right=$(( total_width - title_len - pad_left ))
    
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    local sub_text="by gpfme"
    local sub_len=${#sub_text}
    local sub_pad_left=$(( pad_left + title_len - sub_len ))
    local sub_pad_right=$(( total_width - sub_pad_left - sub_len ))
    local sp_l=$(printf "%${sub_pad_left}s" "")
    local sp_r=$(printf "%${sub_pad_right}s" "")

    # Отрисовка: Градиент рамки прописан жестко прямо в строках
    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_light}│${c_reset}${p_l}${c_white}\e[1m${title_text}${ver_color}${SCRIPT_VERSION}${c_reset}${c_dark}${p_r}│${c_reset}"
    echo -e "${c_dark}${c_reset}${sp_l}${c_gray}${sub_text}${c_reset}${c_dark}${sp_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}"
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

export MENU_CHOICE=""
render_menu() {
    local options=("$@")
    local cur=0

    while [[ "${options[$cur]}" == ---* ]]; do ((cur++)); done
    cursor_off
    printf "\e[H\e[J"

    while true; do
        printf "\e[H"
        draw_header
        
        
        echo -e " ${C_WHITE}[↑↓] Навигация | [Enter] Выбрать | Алиас: ${C_ACCENT}aio_gentle${C_BASE}\e[K"
        echo -e " ${C_DIM}GitHub: ${GITHUB_URL}${C_BASE}\e[K"
        if [[ "$UPDATE_NEEDED" -eq 1 ]]; then
            echo -e " \e[31m● - Требуется обновление (Доступна: v${REMOTE_VERSION})\e[0m\e[K"
        fi
        
        
        echo -e "\e[K"

        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" == ---* ]]; then
                local clean_title="${options[$i]#--- }"
                clean_title="${clean_title% ---}"
                echo -e "  ${C_DIM}::${C_BASE} ${C_ACCENT}${C_BOLD}${clean_title}${C_BASE} ${C_DIM}::${C_BASE}\e[K"
            elif [ "$i" -eq "$cur" ]; then
                echo -e "  ${C_ACCENT}● [ ${options[$i]} ]${C_BASE}\e[K"
            else
                echo -e "      ${C_WHITE}${options[$i]}${C_BASE}\e[K"
            fi
            
            
            if [[ "${options[$i+1]}" == ---* ]]; then
                echo -e "\e[K"
            fi
        done
        printf "\e[J"

        if ! read -rsn3 key; then
            cursor_on; exit 1
        fi

        case "$key" in
            $'\e[A') while true; do ((cur--)); [ "$cur" -lt 0 ] && cur=$((${#options[@]} - 1)); [[ "${options[$cur]}" != ---* ]] && break; done ;;
            $'\e[B') while true; do ((cur++)); [ "$cur" -ge "${#options[@]}" ] && cur=0; [[ "${options[$cur]}" != ---* ]] && break; done ;;
            "") cursor_on; MENU_CHOICE="$cur"; return 0 ;;
        esac
    done
}

# ==========================================
# УТИЛИТЫ ДЛЯ МОДУЛЕЙ
# ==========================================
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

    { eval "$cmd_func"; } >> "$LOG_FILE" 2>&1 &
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

safe_download() { curl -sSL "$1" > "$2"; }
check_installed() { eval "$1" >/dev/null 2>&1 && { echo -e "\n  ${C_OK}[ ИНФО ]${C_BASE} Компонент уже установлен."; return 0; } || return 1; }
wait_for_apt() { while apt-get check 2>&1 | grep -q "lock"; do sleep 5; done; }

# Функции управления скриптом
step_update_script() {
    echo -e "\n${C_ACCENT}Обновление скрипта...${C_BASE}"
    if curl -s --max-time 10 "https://raw.githubusercontent.com/ckpnm/aio_gentle/main/main.sh" -o "$SCRIPT_DIR/main.sh"; then
        chmod +x "$SCRIPT_DIR/main.sh"
        echo -e "${C_OK}Скрипт успешно обновлен! Перезапуск...${C_BASE}"
        sleep 2
        exec bash "$SCRIPT_DIR/main.sh"
    else
        echo -e "${C_ERR}Ошибка при скачивании обновления. Проверьте подключение к сети.${C_BASE}"
        return 1
    fi
}

step_uninstall_script() {
    echo -e "\n${C_ERR}ВНИМАНИЕ: Это действие полностью удалит AIO Gentle Utility.${C_BASE}"
    read -p "Вы уверены, что хотите удалить скрипт? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "Удаление файлов..."
        rm -rf "$SCRIPT_DIR"
        rm -f /usr/local/bin/aio_gentle
        echo -e "${C_OK}Скрипт удален. Выход...${C_BASE}"
        cursor_on
        exit 0
    else
        echo -e "Удаление отменено."
    fi
}

# ==========================================
# ПОДГРУЗКА ВСЕХ МОДУЛЕЙ (Рекурсивно)
# ==========================================
if [ ! -d "$MODULES_DIR" ]; then
    echo -e "${C_ERR}[ ОШИБКА ] Директория modules/ не найдена по пути: $MODULES_DIR${C_BASE}"
    exit 1
fi

while IFS= read -r -d '' f; do
    source "$f"
done < <(find "$MODULES_DIR" -type f -name "*.sh" -print0)

# ==========================================
# ГЛАВНЫЙ ЦИКЛ
# ==========================================
options=(
    "--- ПАНЕЛИ И ПРОКСИ ---"
    "3x-ui"
    "Remnawave"
    "MTProxy (Telegram)"
    "TeleMT"
    "WhatsApp Proxy"
    "--- БАЗОВЫЕ НАСТРОЙКИ ---"
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
    "Обойти белые списки"
    "Обновить скрипт"
    "Удалить скрипт"
    "Информация"
    "Выход"
)

# Проверяем обновления один раз при запуске
check_updates

while true; do
    render_menu "${options[@]}"
    choice=$MENU_CHOICE
    NEEDS_PAUSE=1
    
    clear
    case "${options[$choice]}" in
        "3x-ui") step_3x_ui || NEEDS_PAUSE=0 ;;
        "Remnawave") step_remnawave || NEEDS_PAUSE=0 ;;
        "MTProxy (Telegram)") step_mtproxy || NEEDS_PAUSE=0 ;;
        "TeleMT") step_telemt || NEEDS_PAUSE=0 ;;
        "WhatsApp Proxy") step_whatsapp || NEEDS_PAUSE=0 ;;
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
        "Обойти белые списки") step_bypass_whitelist ;;
        "Обновить скрипт") step_update_script ;;
        "Удалить скрипт") step_uninstall_script ;;
        "Информация") 
            if [ -f "$MODULES_DIR/info.sh" ]; then
                bash "$MODULES_DIR/info.sh"
            else
                echo -e "${C_ERR}Файл info.sh не найден в ${MODULES_DIR}${C_BASE}"
            fi
            ;;
        "Выход") cursor_on; exit 0 ;;
    esac
    
    if [ "$NEEDS_PAUSE" -eq 1 ]; then pause; fi
done
