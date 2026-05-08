# ==============================================================================
# МОДУЛЬ: SSL СЕРТИФИКАТЫ
# ==============================================================================

_do_certbot_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" certbot dnsutils socat curl
}

_do_certbot_run() {
    # Сначала пробуем штатный certbot с Let's Encrypt
    if ! certbot certonly --standalone --agree-tos -m "$LE_EMAIL" -d "$LE_DOMAIN" --non-interactive; then
        echo -e "\nLet's Encrypt временно недоступен. Запускаем резервный выпуск через acme.sh (Let's Encrypt API)..."
        
        # Устанавливаем acme.sh, если его еще нет
        if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
            curl -s https://get.acme.sh | sh >/dev/null 2>&1
        fi
        export PATH="$HOME/.acme.sh:$PATH"
        
        # Подготавливаем директории
        mkdir -p "/etc/letsencrypt/live/$LE_DOMAIN"
        
        # Переключаем acme.sh на Let's Encrypt (по умолчанию он юзает ZeroSSL, который банит .ru)
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
        ~/.acme.sh/acme.sh --register-account -m "$LE_EMAIL" >/dev/null 2>&1
        
        if ~/.acme.sh/acme.sh --issue -d "$LE_DOMAIN" --standalone --force; then
            # Раскидываем ключи в стандартные папки certbot, чтобы другие модули их нашли
            ~/.acme.sh/acme.sh --installcert -d "$LE_DOMAIN" \
                --key-file "/etc/letsencrypt/live/$LE_DOMAIN/privkey.pem" \
                --fullchain-file "/etc/letsencrypt/live/$LE_DOMAIN/fullchain.pem" >/dev/null 2>&1
        else
            exit 1
        fi
    fi
}

_install_cert() {
    clear
    draw_module_header "УСТАНОВКА SSL"
    echo ""
    
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Домен (например, domain.com): ${C_BASE}")" LE_DOMAIN
    if [ -z "$LE_DOMAIN" ]; then cursor_off; return 1; fi
    cursor_off
    export LE_DOMAIN
    
    echo -e "\n  ${C_DIM}Проверка привязки домена к IP...${C_BASE}"
    
    # Получаем IP-адреса для вывода
    local SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null)
    local DOMAIN_IP=$(nslookup "$LE_DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -v ':' | tail -n1)

    if [ -z "$DOMAIN_IP" ]; then
        echo -e "  ${C_ERR}Ошибка: Домен $LE_DOMAIN не резолвится (нет A-записи).${C_BASE}"
        return 1
    fi

    # Розовый цвет для IP
    local c_pink="\e[38;5;204m"
    echo -e "  ${C_WHITE}IP сервера:${C_BASE} ${c_pink}${SERVER_IP}${C_BASE}"
    echo -e "  ${C_WHITE}IP домена: ${C_BASE} ${c_pink}${DOMAIN_IP}${C_BASE}"

    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo -e "  ${C_ERR}Внимание: IP не совпадают!${C_BASE}"
        cursor_on
        read -p "$(echo -e "\n  ${C_ACCENT}${C_BOLD}> Всё равно продолжить установку? (y/n): ${C_BASE}")" force_cont
        cursor_off
        if [[ ! "$force_cont" =~ ^[YyДд] ]]; then 
            echo -e "  ${C_DIM}Отмена. Возврат в меню.${C_BASE}"
            return 1
        fi
    else
        echo -e "  ${C_OK}IP совпадают. Продолжаем...${C_BASE}"
    fi
    
    echo ""
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Email: ${C_BASE}")" LE_EMAIL
    cursor_off
    if [ -z "$LE_EMAIL" ]; then return 1; fi
    export LE_EMAIL
    
    echo ""
    wait_for_apt
    run_module_task "УСТАНОВКА SSL" "Установка пакетов..." "_do_certbot_install"
    
    # Тормозим веб-сервисы, чтобы порт 80 был железно свободен
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    
    run_module_task "УСТАНОВКА SSL" "Выпуск сертификата ($LE_DOMAIN)..." "_do_certbot_run"
    
    # Проверяем, появились ли файлы
    if [ -f "/etc/letsencrypt/live/$LE_DOMAIN/fullchain.pem" ]; then
        if ! grep -q "^${LE_DOMAIN}|" /etc/aio_certs.db 2>/dev/null; then
            echo "$LE_DOMAIN|$(date +%s)" >> /etc/aio_certs.db
        fi
        echo -e "\n  ${C_OK}Сертификат для ${C_WHITE}${LE_DOMAIN}${C_OK} успешно получен.${C_BASE}\n"
        echo -e "  ${C_WHITE}Путь к сертификату: /etc/letsencrypt/live/${LE_DOMAIN}/fullchain.pem${C_BASE}"
        echo -e "  ${C_WHITE}Путь к ключу:       /etc/letsencrypt/live/${LE_DOMAIN}/privkey.pem${C_BASE}"
    else
        echo -e "\n  ${C_ERR}Не удалось получить сертификат. Проверь логи: $LOG_FILE${C_BASE}"
    fi
    
    systemctl start nginx apache2 x-ui 2>/dev/null || true
}

_do_cert_renew() {
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    certbot renew --quiet
    
    # Обновляем acme.sh сертификаты
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" >/dev/null 2>&1
    fi
    
    systemctl start nginx apache2 x-ui 2>/dev/null || true
}

_renew_cert() {
    clear
    draw_module_header "ОБНОВЛЕНИЕ SSL"
    echo ""
    
    if [ ! -f /etc/aio_certs.db ]; then
        echo -e "  ${C_ERR}Нет локально сохраненных сертификатов для обновления.${C_BASE}"
        return
    fi
    
    echo -e "  ${C_ACCENT}${C_BOLD}Выданные сертификаты на сервере:${C_BASE}"
    local CURRENT_TIME=$(date +%s)
    
    while IFS='|' read -r DOMAIN ISSUE_TIME; do
        if [ -n "$DOMAIN" ] && [ -n "$ISSUE_TIME" ]; then
            local DIFF=$(( CURRENT_TIME - ISSUE_TIME ))
            local DAYS_PASSED=$(( DIFF / 86400 ))
            local DAYS_LEFT=$(( 90 - DAYS_PASSED ))
            [[ $DAYS_LEFT -lt 0 ]] && DAYS_LEFT=0
            echo -e "  ${C_WHITE}- ${DOMAIN} ${C_WHITE}(осталось дней: ${DAYS_LEFT})${C_BASE}"
        fi
    done < /etc/aio_certs.db
    
    echo ""
    run_module_task "ОБНОВЛЕНИЕ SSL" "Обновление сертификатов..." "_do_cert_renew"
}

step_letsencrypt() {
    while true; do
        local opts=(
            "Установить сертификат" 
            "Обновить сертификат" 
            "Назад"
        )
        
        if [ -f /etc/aio_certs.db ] && [ -s /etc/aio_certs.db ]; then
            opts+=("--- -------------------- ---")
            opts+=("--- ВЫДАННЫЕ СЕРТИФИКАТЫ ---")
            local CURRENT_TIME=$(date +%s)
            while IFS='|' read -r DOMAIN ISSUE_TIME; do
                if [ -n "$DOMAIN" ] && [ -n "$ISSUE_TIME" ]; then
                    local DIFF=$(( CURRENT_TIME - ISSUE_TIME ))
                    local DAYS_PASSED=$(( DIFF / 86400 ))
                    local DAYS_LEFT=$(( 90 - DAYS_PASSED ))
                    [[ $DAYS_LEFT -lt 0 ]] && DAYS_LEFT=0
                    opts+=("--- $DOMAIN (ост. $DAYS_LEFT дн.) ---")
                fi
            done < /etc/aio_certs.db
        fi

        render_module_menu "SSL СЕРТИФИКАТЫ" "${opts[@]}"
        
        case "$MENU_CHOICE" in
            0) _install_cert; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            1) _renew_cert; echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"; read -rsn1 ;;
            2) return 1 ;; # Выход без паузы, напрямую в меню
        esac
    done
}
