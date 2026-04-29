# ==============================================================================
# МОДУЛЬ: 3X-UI
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

    echo -e "\n${c_dark}╭──${c_light}──────────────────────────────────${c_dark}─╮${c_reset}"
    echo -e "${c_light}│${c_reset}${p_l}${c_white}\e[1m${title}${c_reset}${c_light}${p_r}│${c_reset}"
    echo -e "${c_light}│${c_reset}${sp_l}${c_gray}${sub_text}${c_reset}${c_light}${sp_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}"
}

# Локальная отрисовка меню для x-ui
render_xui_menu() {
    local menu_title="$1"
    shift 
    local options=("$@")
    local cur=0

    while [[ "${options[$cur]}" == ---* ]]; do ((cur++)); done
    cursor_off
    printf "\e[H\e[J"

    while true; do
        printf "\e[H"
        draw_xui_header "$menu_title"
        
        echo -e " ${C_WHITE}[↑↓] Навигация | [Enter] Выбрать${C_BASE}\e[K"
        echo -e " ${C_DIM}GitHub: https://github.com/MHSanaei/3x-ui${C_BASE}\e[K\n\e[K"

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

# Широкий кастомный прогресс-бар для X-UI
_draw_xui_progress() {
    local pid=$1
    local width=37; local p=0; local delay=0.1; local ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        local bar=""
        for ((i=0; i<width; i++)); do
            if [ $i -lt $p ]; then bar+="█"; else bar+="▒"; fi
        done
        printf "\e[u\e[38;5;51m[%s]\e[0m" "$bar"
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
    local full_bar=""
    for ((i=0; i<width; i++)); do full_bar+="█"; done
    printf "\e[u\e[38;5;51m[%s]\e[0m" "$full_bar"
}

# Запуск задачи с отдельным экраном
run_xui_task() {
    local menu_title="$1"
    local task_name="$2"
    local cmd_func="$3"
    
    clear
    draw_xui_header "$menu_title"
    
    echo -e "\n  ${C_ACCENT}${C_BOLD}${task_name}${C_BASE}\n"
    printf "  \e[s" 
    
    { eval "$cmd_func"; } >> "$LOG_FILE" 2>&1 &
    local task_pid=$!

    _draw_xui_progress "$task_pid" &
    local bar_pid=$!

    wait $task_pid
    local exit_code=$?
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    
    echo -e "\n"
    if [ $exit_code -ne 0 ]; then
        echo -e "  ${C_ERR}✗ Ошибка (см. логи: $LOG_FILE)${C_BASE}"
        cursor_on; exit 1
    fi
    sleep 0.5
}

_do_certbot_xui() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq && apt-get install -y -qq certbot
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    certbot certonly --standalone --agree-tos -m "admin@$XUI_DOMAIN" -d "$XUI_DOMAIN" --non-interactive
}

_do_acme_ip_xui() {
    curl -s https://get.acme.sh | sh
    mkdir -p /root/cert/ip
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    
    local SERVER_IP=$(curl -s4 ifconfig.me)
    local d_args="-d ${SERVER_IP}"
    
    if [ "$INCLUDE_V6" == "1" ]; then
        local SERVER_IPV6=$(curl -s6 ifconfig.me)
        [ -n "$SERVER_IPV6" ] && d_args+=" -d ${SERVER_IPV6}"
    fi
    
    ~/.acme.sh/acme.sh --register-account -m "$ZERO_SSL_EMAIL" --server zerossl >/dev/null 2>&1
    ~/.acme.sh/acme.sh --set-default-ca --server zerossl
    ~/.acme.sh/acme.sh --issue $d_args --standalone --server zerossl --force
    ~/.acme.sh/acme.sh --installcert -d ${SERVER_IP} --key-file "/root/cert/ip/privkey.pem" --fullchain-file "/root/cert/ip/fullchain.pem"
}

_do_install_3xui() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq jq tar curl
    local arch
    case "$(uname -m)" in
        x86_64 | amd64 | x64) arch="amd64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *) exit 1 ;;
    esac
    
    local tag=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | jq -r .tag_name)
    curl -L -o /tmp/x-ui.tar.gz "https://github.com/MHSanaei/3x-ui/releases/download/${tag}/x-ui-linux-${arch}.tar.gz"
    
    cd /usr/local/
    tar zxvf /tmp/x-ui.tar.gz >/dev/null
    rm /tmp/x-ui.tar.gz
    
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    
    curl -L -o /etc/systemd/system/x-ui.service "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.debian"
    systemctl daemon-reload
    systemctl enable --now x-ui
}

_do_config_3xui() {
    sleep 2
    /usr/local/x-ui/x-ui setting -username "$XUI_USER" -password "$XUI_PASS" -port "$XUI_PORT" -webBasePath "$XUI_PATH"
    
    if [ -n "$CERT_PUB" ] && [ -f "$CERT_PUB" ]; then
        /usr/local/x-ui/x-ui cert -webCert "$CERT_PUB" -webCertKey "$CERT_KEY"
    fi
    systemctl restart x-ui
}

draw_dynamic_success_box() {
    clear # Очищаем экран от логов установки
    local user="$1"
    local pass="$2"
    local port="$3"
    local path="$4"
    local url="$5"
    local cert="$6"
    local key="$7"

    local c_light="\e[38;5;51m"
    local c_dark="\e[38;5;24m"
    local c_white="\e[38;5;255m"
    local c_reset="\e[0m"

    local lines=()
    lines+=("Username:    $user")
    lines+=("Password:    $pass")
    lines+=("Port:        $port")
    lines+=("WebBasePath: $path")
    lines+=("Access URL:  $url")
    
    if [ -n "$cert" ] && [ -n "$key" ]; then
        lines+=("Cert Path:   $cert")
        lines+=("Key Path:    $key")
    fi
    
    local max_len=40
    for s in "${lines[@]}"; do
        if [ ${#s} -gt $max_len ]; then max_len=${#s}; fi
    done
    
    local box_width=$((max_len + 4))
    
    local top_dashes=$(printf "%$((box_width - 3))s" "" | tr ' ' '─')
    local top_box="${c_dark}╭──${c_light}${top_dashes}${c_dark}─╮${c_reset}"
    
    local bot_dashes=$(printf "%${box_width}s" "" | tr ' ' '─')
    local bot_box="${c_dark}╰${bot_dashes}╯${c_reset}"
    
    local mid_dashes=$(printf "%${box_width}s" "" | tr ' ' '─')
    local sep_box="${c_dark}├${mid_dashes}┤${c_reset}"

    local pipe="${c_light}│${c_reset}"
    
    local title="ПАНЕЛЬ 3X-UI УСПЕШНО УСТАНОВЛЕНА"
    local pad=$((box_width - ${#title} - 2))
    [ $pad -lt 0 ] && pad=0
    local title_spaces=$(printf "%${pad}s" "")

    echo -e "\n${top_box}"
    echo -e "${pipe}  ${C_OK}${title}${C_ACCENT}${title_spaces}${pipe}"
    echo -e "${sep_box}"
    
    local u_pad=$((box_width - ${#lines[0]} - 2))
    echo -e "${pipe}  ${C_WHITE}Username:${C_BASE}    ${user}$(printf "%${u_pad}s" "")${pipe}"
    
    local p_pad=$((box_width - ${#lines[1]} - 2))
    echo -e "${pipe}  ${C_WHITE}Password:${C_BASE}    ${pass}$(printf "%${p_pad}s" "")${pipe}"
    
    local po_pad=$((box_width - ${#lines[2]} - 2))
    echo -e "${pipe}  ${C_WHITE}Port:${C_BASE}        ${port}$(printf "%${po_pad}s" "")${pipe}"
    
    local pa_pad=$((box_width - ${#lines[3]} - 2))
    echo -e "${pipe}  ${C_WHITE}WebBasePath:${C_BASE} ${path}$(printf "%${pa_pad}s" "")${pipe}"
    
    local ur_pad=$((box_width - ${#lines[4]} - 2))
    echo -e "${pipe}  ${C_WHITE}Access URL:${C_BASE}  ${C_ACCENT}${url}${C_BASE}$(printf "%${ur_pad}s" "")${pipe}"
    
    if [ -n "$cert" ] && [ -n "$key" ]; then
        echo -e "${sep_box}"
        local c_pad=$((box_width - ${#lines[5]} - 2))
        echo -e "${pipe}  ${C_WHITE}Cert Path:${C_BASE}   ${cert}$(printf "%${c_pad}s" "")${pipe}"
        
        local k_pad=$((box_width - ${#lines[6]} - 2))
        echo -e "${pipe}  ${C_WHITE}Key Path:${C_BASE}    ${key}$(printf "%${k_pad}s" "")${pipe}"
    fi
    
    echo -e "${bot_box}\n"
}

_setup_3x_ui() {
    if check_installed "[ -d /usr/local/x-ui ]"; then return; fi

    # Селектор для порта
    local port_opts=("Сгенерировать случайный порт" "Указать свой порт")
    render_xui_menu "ПОРТ ПАНЕЛИ 3X-UI" "${port_opts[@]}"
    if [ "$MENU_CHOICE" -eq 1 ]; then
        clear
        draw_xui_header "ПОРТ ПАНЕЛИ 3X-UI"
        echo -e "\n"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (1024-65535): ${C_BASE}")" XUI_PORT
        cursor_off
    else
        XUI_PORT=$(shuf -i 10000-60000 -n 1)
        clear
        draw_xui_header "ПОРТ ПАНЕЛИ 3X-UI"
        echo -e "\n  ${C_OK}Сгенерирован случайный порт: ${XUI_PORT}${C_BASE}"
        sleep 1
    fi
    export XUI_PORT

    local ssl_opts=(
        "Выпустить SSL для домена (certbot)"
        "Выпустить SSL для IP (acme.sh + ZeroSSL)"
    )
    local saved_domains=()
    
    if [ -f /etc/aio_certs.db ]; then
        while IFS='|' read -r DOMAIN ISSUE_TIME; do
            if [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
                ssl_opts+=("Локальный SSL: $DOMAIN")
                saved_domains+=("$DOMAIN")
            fi
        done < /etc/aio_certs.db
    fi
    
    ssl_opts+=("Указать пути к файлам вручную")
    ssl_opts+=("Без SSL (Небезопасно)")

    while true; do
        render_xui_menu "SSL ДЛЯ ПАНЕЛИ 3X-UI" "${ssl_opts[@]}"
        local ssl_choice=$MENU_CHOICE
        break
    done
    
    export CERT_PUB=""
    export CERT_KEY=""
    export XUI_HOST=$(curl -s4 ifconfig.me)
    export INCLUDE_V6=0

    local total_opts=${#ssl_opts[@]}
    local manual_idx=$((total_opts - 2))
    local nossl_idx=$((total_opts - 1))

    if [ "$ssl_choice" -eq 0 ]; then
        clear
        draw_xui_header "SSL ДЛЯ ПАНЕЛИ 3X-UI"
        echo -e "\n"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи домен: ${C_BASE}")" XUI_DOMAIN
        export XUI_DOMAIN
        cursor_off
        run_xui_task "SSL ДЛЯ ПАНЕЛИ 3X-UI" "Выпуск сертификата (certbot)..." "_do_certbot_xui"
        CERT_PUB="/etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem"
        CERT_KEY="/etc/letsencrypt/live/${XUI_DOMAIN}/privkey.pem"
        XUI_HOST=$XUI_DOMAIN
        
    elif [ "$ssl_choice" -eq 1 ]; then
        clear
        draw_xui_header "SSL ДЛЯ ПАНЕЛИ 3X-UI"
        echo -e "\n  ${C_DIM}ZeroSSL требует email для регистрации аккаунта.${C_BASE}"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи email: ${C_BASE}")" ZERO_SSL_EMAIL
        export ZERO_SSL_EMAIL
        cursor_off

        if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" -eq 0 ]; then
            local v6_opts=("Включить IPv6 в сертификат" "Не включать IPv6" "Отключить IPv6 на сервере")
            render_xui_menu "НАЙДЕН IPv6" "${v6_opts[@]}"
            local v6_choice=$MENU_CHOICE
            if [ $v6_choice -eq 0 ]; then INCLUDE_V6=1; fi
            if [ $v6_choice -eq 2 ]; then 
                run_xui_task "ОТКЛЮЧЕНИЕ IPv6" "Отключение протокола IPv6..." "sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null && sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null"
            fi
        fi
        run_xui_task "SSL ДЛЯ ПАНЕЛИ 3X-UI" "Выпуск сертификата (acme.sh + ZeroSSL)..." "_do_acme_ip_xui"
        CERT_PUB="/root/cert/ip/fullchain.pem"
        CERT_KEY="/root/cert/ip/privkey.pem"
        
    elif [ "$ssl_choice" -eq "$manual_idx" ]; then
        clear
        draw_xui_header "SSL ДЛЯ ПАНЕЛИ 3X-UI"
        echo -e "\n"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Путь к сертификату (.crt / fullchain): ${C_BASE}")" CERT_PUB
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Путь к ключу (.key / privkey): ${C_BASE}")" CERT_KEY
        export CERT_PUB CERT_KEY
        cursor_off
        
    elif [ "$ssl_choice" -eq "$nossl_idx" ]; then
        clear
        draw_xui_header "SSL ДЛЯ ПАНЕЛИ 3X-UI"
        echo -e "\n  ${C_DIM}Установка продолжается без SSL...${C_BASE}"
        sleep 1
    else
        local sel_idx=$((ssl_choice - 2))
        local sel_domain="${saved_domains[$sel_idx]}"
        CERT_PUB="/etc/letsencrypt/live/${sel_domain}/fullchain.pem"
        CERT_KEY="/etc/letsencrypt/live/${sel_domain}/privkey.pem"
        XUI_HOST="$sel_domain"
        clear
        draw_xui_header "SSL ДЛЯ ПАНЕЛИ 3X-UI"
        echo -e "\n  ${C_OK}Выбран локальный сертификат: ${sel_domain}${C_BASE}"
        sleep 1
    fi

    export XUI_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    export XUI_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    export XUI_PATH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

    wait_for_apt
    run_xui_task "УСТАНОВКА 3X-UI" "Загрузка и установка ядра 3x-ui..." "_do_install_3xui"
    run_xui_task "УСТАНОВКА 3X-UI" "Применение параметров и SSL..." "_do_config_3xui"

    local protocol="http"
    if [ -n "$CERT_PUB" ] && [ -f "$CERT_PUB" ]; then protocol="https"; fi
    
    local final_url="${protocol}://${XUI_HOST}:${XUI_PORT}/${XUI_PATH}/"
    
    draw_dynamic_success_box "$XUI_USER" "$XUI_PASS" "$XUI_PORT" "$XUI_PATH" "$final_url" "$CERT_PUB" "$CERT_KEY"
}

_manage_3x_ui() {
    if [ ! -d /usr/local/x-ui ]; then
        clear
        draw_xui_header "УПРАВЛЕНИЕ 3X-UI"
        echo -e "\n  ${C_ERR}Панель 3x-ui не установлена!${C_BASE}"
        echo -e "\n"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Установить сейчас? (y/n): ${C_BASE}")" want_install
        cursor_off
        if [[ "$want_install" =~ ^[YyДд] ]]; then
            _setup_3x_ui
        fi
        return
    fi
    
    local opts=(
        "Запустить" 
        "Остановить" 
        "Перезапустить" 
        "Показать логи" 
        "Сбросить суперадмина" 
        "Сбросить вебпуть" 
        "Сбросить настройки сети" 
        "Назад"
    )
    
    while true; do
        render_xui_menu "УПРАВЛЕНИЕ 3X-UI" "${opts[@]}"
        local choice=$MENU_CHOICE
        
        if [ "$choice" -eq 7 ]; then return 0; fi
        
        case $choice in
            0) run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Запуск службы x-ui..." "systemctl start x-ui" ;;
            1) run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Остановка службы x-ui..." "systemctl stop x-ui" ;;
            2) run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Перезапуск службы x-ui..." "systemctl restart x-ui" ;;
            3) clear; /usr/local/x-ui/x-ui log ;;
            4)
               local new_user=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
               local new_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
               run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Смена учетных данных..." "/usr/local/x-ui/x-ui setting -username $new_user -password $new_pass"
               echo -e "  ${C_OK}Новые данные для входа:${C_BASE}"
               echo -e "  ${C_WHITE}Username:${C_BASE} $new_user"
               echo -e "  ${C_WHITE}Password:${C_BASE} $new_pass"
               run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Перезапуск службы..." "systemctl restart x-ui"
               ;;
            5)
               local new_path=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
               run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Смена WebBasePath..." "/usr/local/x-ui/x-ui setting -webBasePath $new_path"
               echo -e "  ${C_OK}Новый WebBasePath:${C_BASE} $new_path"
               run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Перезапуск службы..." "systemctl restart x-ui"
               ;;
            6) 
               run_xui_task "УПРАВЛЕНИЕ 3X-UI" "Сброс сетевых настроек..." "/usr/local/x-ui/x-ui clear_network" 
               echo -e "  ${C_DIM}Настройки портов и сети сброшены на дефолтные.${C_BASE}"
               ;;
        esac
        pause
    done
}

_do_uninstall_3xui() {
    systemctl stop x-ui 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    rm -rf /usr/local/x-ui
    rm -f /etc/systemd/system/x-ui.service
    systemctl daemon-reload
}

_uninstall_3x_ui() {
    local un_opts=("Да, удалить панель и все базы данных" "Отмена")
    render_xui_menu "УДАЛЕНИЕ 3X-UI" "${un_opts[@]}"
    if [ "$MENU_CHOICE" -eq 0 ]; then
        run_xui_task "УДАЛЕНИЕ 3X-UI" "Удаление ядра и файлов конфигурации..." "_do_uninstall_3xui"
        echo -e "  ${C_OK}Удаление успешно завершено.${C_BASE}"
    else
        echo -e "\n  ${C_DIM}Отмена.${C_BASE}"
    fi
}

step_3x_ui() {
    local opts=("Установить 3x-ui" "Управление 3x-ui" "Удалить 3x-ui" "Назад")
    while true; do
        render_xui_menu "3X-UI" "${opts[@]}"
        local local_choice=$MENU_CHOICE
        case $local_choice in
            0) _setup_3x_ui; pause ;;
            1) _manage_3x_ui ;;
            2) _uninstall_3x_ui; pause ;;
            3) return 1 ;;
        esac
    done
}
