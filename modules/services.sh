# -------------------- 3X-UI --------------------
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
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    ~/.acme.sh/acme.sh --issue $d_args --standalone --server letsencrypt --certificate-profile shortlived --days 6 --httpport 80 --force
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
    cd /usr/local/ && tar zxvf /tmp/x-ui.tar.gz >/dev/null && rm /tmp/x-ui.tar.gz
    cd x-ui && chmod +x x-ui bin/xray-linux-${arch}
    curl -L -o /etc/systemd/system/x-ui.service "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.debian"
    systemctl daemon-reload && systemctl enable --now x-ui
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
    local user="$1" pass="$2" port="$3" path="$4" url="$5" cert="$6" key="$7"
    local lines=("Username:    $user" "Password:    $pass" "Port:        $port" "WebBasePath: $path" "Access URL:  $url")
    if [ -n "$cert" ] && [ -n "$key" ]; then lines+=("Cert Path:   $cert" "Key Path:    $key"); fi
    local max_len=40
    for s in "${lines[@]}"; do if [ ${#s} -gt $max_len ]; then max_len=${#s}; fi; done
    local box_width=$((max_len + 4)); local top_border=""
    for ((i=0; i<box_width; i++)); do top_border+="─"; done
    local title="ПАНЕЛЬ 3X-UI УСПЕШНО УСТАНОВЛЕНА"
    local pad=$((box_width - ${#title} - 2)); [ $pad -lt 0 ] && pad=0
    echo -e "\n${C_ACCENT}┌${top_border}┐${C_BASE}"
    echo -e "${C_ACCENT}│  ${C_OK}${title}${C_ACCENT}$(printf "%${pad}s" "")│${C_BASE}"
    echo -e "${C_ACCENT}├${top_border}┤${C_BASE}"
    for line in "${lines[@]}"; do
        local l_pad=$((box_width - ${#line} - 2))
        local key_part="${line%%:*}"
        local val_part="${line#*: }"
        echo -e "${C_ACCENT}│  ${C_WHITE}${key_part}:${C_BASE} ${val_part}$(printf "%${l_pad}s" "")  ${C_ACCENT}│${C_BASE}"
    done
    echo -e "${C_ACCENT}└${top_border}┘${C_BASE}\n"
}

_setup_3x_ui() {
    echo -e "\n${C_ACCENT}[ 3X-UI ] УСТАНОВКА${C_BASE}\n"
    if check_installed "[ -d /usr/local/x-ui ]"; then return; fi
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Установить свой порт? (y/n): ${C_BASE}")" custom_port
    if [[ "$custom_port" =~ ^[YyДд] ]]; then
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи порт (1024-65535): ${C_BASE}")" XUI_PORT
    else
        XUI_PORT=$(shuf -i 10000-60000 -n 1)
        echo -e "  ${C_OK}Сгенерирован порт: ${XUI_PORT}${C_BASE}"
    fi
    export XUI_PORT
    local ssl_opts=("Выпустить SSL для домена (certbot)" "Выпустить SSL для IP (acme.sh | ~6 дней)")
    local saved_domains=()
    if [ -f /etc/aio_certs.db ]; then
        while IFS='|' read -r DOMAIN ISSUE_TIME; do
            if [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
                ssl_opts+=("Локальный SSL: $DOMAIN")
                saved_domains+=("$DOMAIN")
            fi
        done < /etc/aio_certs.db
    fi
    ssl_opts+=("Указать пути к файлам вручную" "Без SSL (Небезопасно)")
    render_menu "SSL ДЛЯ ПАНЕЛИ 3X-UI" "${ssl_opts[@]}"
    local ssl_choice=$MENU_CHOICE
    export CERT_PUB="" CERT_KEY="" XUI_HOST=$(curl -s4 ifconfig.me) INCLUDE_V6=0
    clear
    local total_opts=${#ssl_opts[@]}
    local manual_idx=$((total_opts - 2))
    local nossl_idx=$((total_opts - 1))
    if [ "$ssl_choice" -eq 0 ]; then
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Введи домен: ${C_BASE}")" XUI_DOMAIN
        export XUI_DOMAIN; cursor_off
        run_task "Выпуск сертификата (certbot)" "_do_certbot_xui"
        CERT_PUB="/etc/letsencrypt/live/${XUI_DOMAIN}/fullchain.pem"
        CERT_KEY="/etc/letsencrypt/live/${XUI_DOMAIN}/privkey.pem"
        XUI_HOST=$XUI_DOMAIN
    elif [ "$ssl_choice" -eq 1 ]; then
        if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" -eq 0 ]; then
            render_menu "НАЙДЕН IPv6" "Включить IPv6 в сертификат" "Не включать IPv6"
            [ "$MENU_CHOICE" -eq 0 ] && INCLUDE_V6=1
        fi
        clear
        run_task "Выпуск сертификата (acme.sh)" "_do_acme_ip_xui"
        CERT_PUB="/root/cert/ip/fullchain.pem"
        CERT_KEY="/root/cert/ip/privkey.pem"
    elif [ "$ssl_choice" -eq "$manual_idx" ]; then
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Путь к crt: ${C_BASE}")" CERT_PUB
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Путь к key: ${C_BASE}")" CERT_KEY
        export CERT_PUB CERT_KEY; cursor_off
    elif [ "$ssl_choice" -ne "$nossl_idx" ]; then
        local sel_idx=$((ssl_choice - 2))
        local sel_domain="${saved_domains[$sel_idx]}"
        CERT_PUB="/etc/letsencrypt/live/${sel_domain}/fullchain.pem"
        CERT_KEY="/etc/letsencrypt/live/${sel_domain}/privkey.pem"
        XUI_HOST="$sel_domain"
    fi
    export XUI_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    export XUI_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    export XUI_PATH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    clear
    echo -e "\n${C_ACCENT}[ 3X-UI ] УСТАНОВКА ЯДРА${C_BASE}\n"
    wait_for_apt
    run_task "Загрузка и установка 3x-ui" "_do_install_3xui"
    run_task "Применение параметров и SSL" "_do_config_3xui"
    local protocol="http"
    if [ -n "$CERT_PUB" ] && [ -f "$CERT_PUB" ]; then protocol="https"; fi
    local final_url="${protocol}://${XUI_HOST}:${XUI_PORT}/${XUI_PATH}/"
    draw_dynamic_success_box "$XUI_USER" "$XUI_PASS" "$XUI_PORT" "$XUI_PATH" "$final_url" "$CERT_PUB" "$CERT_KEY"
}

_manage_3x_ui() {
    if [ ! -d /usr/local/x-ui ]; then
        cursor_on
        read -p "$(echo -e "  ${C_ERR}Панель не установлена! Установить? (y/n): ${C_BASE}")" want_install
        cursor_off
        if [[ "$want_install" =~ ^[YyДд] ]]; then clear; _setup_3x_ui; fi
        return
    fi
    local opts=("Запустить" "Остановить" "Перезапустить" "Показать логи" "Сбросить суперадмина" "Сбросить вебпуть" "Сбросить настройки сети" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ 3X-UI" "${opts[@]}"
        local choice=$MENU_CHOICE
        if [ "$choice" -eq 7 ]; then return 0; fi
        clear
        echo -e "\n${C_ACCENT}[ 3X-UI ] ВЫПОЛНЕНИЕ КОМАНДЫ${C_BASE}\n"
        case $choice in
            0) run_task "Запуск службы" "systemctl start x-ui" ;;
            1) run_task "Остановка службы" "systemctl stop x-ui" ;;
            2) run_task "Перезапуск службы" "systemctl restart x-ui" ;;
            3) /usr/local/x-ui/x-ui log ;;
            4)
               local new_user=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
               local new_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
               run_task "Смена данных" "/usr/local/x-ui/x-ui setting -username $new_user -password $new_pass"
               echo -e "  ${C_OK}Новые данные: ${C_WHITE}$new_user / $new_pass${C_BASE}"
               systemctl restart x-ui ;;
            5)
               local new_path=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
               run_task "Смена WebBasePath" "/usr/local/x-ui/x-ui setting -webBasePath $new_path"
               echo -e "  ${C_OK}Новый путь: ${C_WHITE}$new_path${C_BASE}"
               systemctl restart x-ui ;;
            6) run_task "Сброс сети" "/usr/local/x-ui/x-ui clear_network" ;;
        esac
        echo -e "\n${C_OK}Нажми любую клавишу...${C_BASE}"; read -rsn1
    done
}

_uninstall_3x_ui() {
    echo -e "\n${C_ACCENT}[ 3X-UI ] УДАЛЕНИЕ${C_BASE}\n"
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Точно удалить панель 3x-ui? (y/n): ${C_BASE}")" confirm
    cursor_off
    if [[ "$confirm" =~ ^[YyДд] ]]; then
        run_task "Удаление 3x-ui" "systemctl stop x-ui; systemctl disable x-ui; rm -rf /usr/local/x-ui /etc/systemd/system/x-ui.service; systemctl daemon-reload"
    fi
}

step_3x_ui() {
    local opts=("Установить 3x-ui" "Управление 3x-ui" "Удалить 3x-ui" "Назад")
    while true; do
        render_menu "ПАНЕЛЬ 3X-UI" "${opts[@]}"
        case $MENU_CHOICE in
            0) clear; _setup_3x_ui; echo -e "\n${C_OK}Нажми любую клавишу...${C_BASE}"; read -rsn1 ;;
            1) clear; _manage_3x_ui ;;
            2) clear; _uninstall_3x_ui ;;
            3) return 1 ;;
        esac
    done
}

# -------------------- DOCKER --------------------
step_docker() {
    local opts=("Установить Docker" "Удалить Docker" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ DOCKER" "${opts[@]}"
        clear
        case $MENU_CHOICE in
            0) run_task "Установка Docker" "curl -fsSL https://get.docker.com | sh"; run_task "Запуск" "systemctl enable --now docker"; return 0 ;;
            1) run_task "Удаление Docker" "apt-get purge -y -qq docker-engine docker docker.io docker-ce docker-ce-cli containerd.io; rm -rf /var/lib/docker"; return 0 ;;
            2) return 1 ;;
        esac
    done
}

# -------------------- ADGUARD HOME --------------------
_do_adguard_bin() {
    systemctl stop AdGuardHome 2>/dev/null; rm -rf /opt/AdGuardHome /etc/systemd/system/AdGuardHome.service
    curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
}
_install_adguard() {
    if check_installed "[ -d /opt/AdGuardHome ]"; then return; fi
    run_task "Освобождение порта 53" "systemctl stop systemd-resolved 2>/dev/null; echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    run_task "Установка бинарника" "_do_adguard_bin"
    echo -e "\n  ${C_OK}Установлено! Настрой интерфейс по адресу: http://$(curl -s4 ifconfig.me):3000${C_BASE}"
    echo -e "  ${C_ERR}ОБЯЗАТЕЛЬНО: В настройках смени веб-порт с 80 на 3000.${C_BASE}"
}
step_adguard() {
    local opts=("Установить AdGuard Home" "Обновить AdGuard Home" "Удалить AdGuard Home" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ ADGUARD HOME" "${opts[@]}"
        clear
        case $MENU_CHOICE in
            0) _install_adguard; return 0 ;;
            1) run_task "Обновление" "/opt/AdGuardHome/AdGuardHome -s update"; return 0 ;;
            2) run_task "Удаление" "/opt/AdGuardHome/AdGuardHome -s uninstall; rm -rf /opt/AdGuardHome"; return 0 ;;
            3) return 1 ;;
        esac
    done
}

# -------------------- BESZEL & WARP --------------------
step_beszel() {
    local opts=("Установить HUB" "Установить Agent" "Удалить Beszel" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ BESZEL" "${opts[@]}"
        clear
        case $MENU_CHOICE in
            0) run_task "Установка HUB" "curl -sL https://github.com/henrygd/beszel/releases/latest/download/beszel_Linux_amd64.tar.gz | tar -xz -C /opt"; return 0 ;;
            1) echo "В разработке..."; return 0 ;;
            2) run_task "Удаление" "rm -rf /opt/beszel*"; return 0 ;;
            3) return 1 ;;
        esac
    done
}
step_warp() {
    local opts=("Установить WARP" "Удалить WARP" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ WARP" "${opts[@]}"
        clear
        case $MENU_CHOICE in
            0) run_task "Установка WARP" "bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)"; return 0 ;;
            1) run_task "Удаление WARP" "bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh)"; return 0 ;;
            2) return 1 ;;
        esac
    done
}
