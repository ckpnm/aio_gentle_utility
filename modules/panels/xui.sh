# ==============================================================================
# МОДУЛЬ: 3X-UI (v1.06 - Fixed Firewall & SubPort)
# ==============================================================================

# Локальная отрисовка шапки для x-ui
draw_xui_header() {
    local title="$1"
    local c_light="\e[38;5;51m"
    local c_dark="\e[38;5;24m"
    local c_white="\e[38;5;255m"
    local c_gray="\e[38;5;244m"
    local c_reset="\e[0m"

    local total_width=37
    local title_len=${#title}
    
    if (( title_len > total_width - 4 )); then
        title="${title:0:31}.."
        title_len=${#title}
    fi

    local pad_left=$(( (total_width - title_len) / 2 ))
    local pad_right=$(( total_width - title_len - pad_left ))
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    local sub_text="by MHSanaei"
    local sub_len=${#sub_text}
    
    local sub_pad_left=$(( pad_left + title_len - sub_len ))
    if (( sub_pad_left < 2 || sub_pad_left + sub_len > total_width - 2 )); then
        sub_pad_left=$(( (total_width - sub_len) / 2 ))
    fi
    local sub_pad_right=$(( total_width - sub_pad_left - sub_len ))
    
    local sp_l=$(printf "%${sub_pad_left}s" "")
    local sp_r=$(printf "%${sub_pad_right}s" "")

    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_dark}│${c_reset}${p_l}${c_white}\e[1m${title}${c_reset}${c_light}${p_r}│${c_reset}"
    echo -e "${c_dark}│${c_reset}${sp_l}${c_gray}${sub_text}${c_reset}${c_light}${sp_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}"
}

# Функция для принудительного открытия портов
_open_firewall_ports() {
    local p1=$1
    local p2=$2
    # Открываем в UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$p1"/tcp >/dev/null 2>&1
        ufw allow "$p2"/tcp >/dev/null 2>&1
    fi
    # Открываем в iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$p1" -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p tcp --dport "$p2" -j ACCEPT >/dev/null 2>&1
    fi
}

_do_config_3xui() {
    sleep 2
    # 1. Настройка основных параметров (Порт панели, Юзер, Пароль, Путь со слэшами)
    /usr/local/x-ui/x-ui setting -username "$XUI_USER" -password "$XUI_PASS" -port "$XUI_PORT" -webBasePath "/${XUI_PATH}/"
    
    # 2. Настройка порта подписки
    /usr/local/x-ui/x-ui setting -subPort "$XUI_SUB_PORT"
    
    # 3. Применение SSL
    if [ -n "$CERT_PUB" ] && [ -f "$CERT_PUB" ]; then
        /usr/local/x-ui/x-ui cert -webCert "$CERT_PUB" -webCertKey "$CERT_KEY"
    fi
    
    systemctl restart x-ui
}

# Отрисовка финального бокса (добавлен порт подписки)
draw_dynamic_success_box() {
    clear
    local user="$1"; local pass="$2"; local port="$3"; local path="$4"; local url="$5"; local sub="$6"
    local c_light="\e[38;5;51m"; local c_dark="\e[38;5;24m"; local c_white="\e[38;5;255m"; local c_reset="\e[0m"

    local lines=()
    lines+=("Username:    $user")
    lines+=("Password:    $pass")
    lines+=("Panel Port:  $port")
    lines+=("Sub Port:    $sub")
    lines+=("WebBasePath: /$path/")
    lines+=("Access URL:  $url")
    
    local max_len=40
    for s in "${lines[@]}"; do [ ${#s} -gt $max_len ] && max_len=${#s}; done
    local box_width=$((max_len + 4))
    
    local h_line=""; for ((i=0; i<box_width; i++)); do h_line+="─"; done
    local top_box="${c_light}╭${h_line}╮${c_reset}"
    local bot_box="${c_dark}╰${h_line}╯${c_reset}"
    local sep_box="${c_dark}├${h_line}${c_reset}${c_light}┤${c_reset}"
    local pipe_l="${c_dark}│${c_reset}"; local pipe_r="${c_light}│${c_reset}"
    
    echo -e "\n${top_box}"
    echo -e "${pipe_l}  \e[1;36mПАНЕЛЬ 3X-UI УСПЕШНО УСТАНОВЛЕНА\e[0m$(printf "%$((box_width - 32))s" "")${pipe_r}"
    echo -e "${sep_box}"
    for line in "${lines[@]}"; do
        local p=$(($box_width - ${#line} - 2))
        echo -e "${pipe_l}  ${c_white}${line}$(printf "%${p}s" "")${pipe_r}"
    done
    echo -e "${bot_box}\n"
}

_setup_3x_ui() {
    if check_installed "[ -d /usr/local/x-ui ]"; then return; fi

    # 1. ПОРТ ПАНЕЛИ
    local port_opts=("Сгенерировать случайный порт панели" "Указать свой порт панели")
    render_xui_menu "ПОРТ ПАНЕЛИ 3X-UI" "${port_opts[@]}"
    if [ "$MENU_CHOICE" -eq 1 ]; then
        clear; draw_xui_header "ПОРТ ПАНЕЛИ 3X-UI"; echo -e "\n"; cursor_on
        read -p "$(echo -e "  \e[1;36m> Введи порт (1024-65535): \e[0m")" XUI_PORT; cursor_off
    else
        XUI_PORT=$(shuf -i 10000-60000 -n 1)
        clear; draw_xui_header "ПОРТ ПАНЕЛИ 3X-UI"; echo -e "\n  \e[1;36mСгенерирован порт панели: ${XUI_PORT}\e[0m"; sleep 1
    fi

    # 2. ПОРТ ПОДПИСКИ
    local sub_opts=("Сгенерировать случайный порт подписки" "Указать свой порт подписки")
    render_xui_menu "ПОРТ ПОДПИСКИ 3X-UI" "${sub_opts[@]}"
    if [ "$MENU_CHOICE" -eq 1 ]; then
        clear; draw_xui_header "ПОРТ ПОДПИСКИ 3X-UI"; echo -e "\n"; cursor_on
        read -p "$(echo -e "  \e[1;36m> Введи порт (1024-65535): \e[0m")" XUI_SUB_PORT; cursor_off
    else
        XUI_SUB_PORT=$(shuf -i 10000-60000 -n 1)
        clear; draw_xui_header "ПОРТ ПОДПИСКИ 3X-UI"; echo -e "\n  \e[1;36mСгенерирован порт подписки: ${XUI_SUB_PORT}\e[0m"; sleep 1
    fi

    # 3. ПРИНУДИТЕЛЬНОЕ ОТКРЫТИЕ ПОРТОВ
    _open_firewall_ports "$XUI_PORT" "$XUI_SUB_PORT"

    # ... далее идет блок выбора SSL (оставляем без изменений) ...
    # [Тут должен быть твой блок выбора SSL]
    
    # Генерация данных
    export XUI_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    export XUI_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    export XUI_PATH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

    wait_for_apt
    run_xui_task "УСТАНОВКА 3X-UI" "Загрузка и установка ядра 3x-ui..." "_do_install_3xui"
    run_xui_task "УСТАНОВКА 3X-UI" "Применение параметров и SSL..." "_do_config_3xui"

    local protocol="http"
    [ -n "$CERT_PUB" ] && [ -f "$CERT_PUB" ] && protocol="https"
    local final_url="${protocol}://${XUI_HOST}:${XUI_PORT}/${XUI_PATH}/"
    
    draw_dynamic_success_box "$XUI_USER" "$XUI_PASS" "$XUI_PORT" "$XUI_PATH" "$final_url" "$XUI_SUB_PORT"
}
