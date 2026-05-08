# ==============================================================================
# МОДУЛЬ: SSL СЕРТИФИКАТЫ
# ==============================================================================

_do_certbot_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" certbot dnsutils
}

_do_certbot_run() {
    # Пытаемся получить сертификат от Let's Encrypt
    if ! certbot certonly --standalone --agree-tos -m "$LE_EMAIL" -d "$LE_DOMAIN" --non-interactive; then
        echo "Let's Encrypt недоступен. Пробуем альтернативный CA (Buypass)..."
        # Если Let's Encrypt лежит (ошибка 500/maintenance), используем Buypass (работает точно так же)
        certbot certonly --standalone --agree-tos -m "$LE_EMAIL" -d "$LE_DOMAIN" --non-interactive --server 'https://api.buypass.com/acme/directory'
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
    
    echo -e "\n  ${C_DIM}Проверка привязки домена к IP...${C_BASE}"
    
    # Получаем IP явно и выводим пользователю
    local SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null)
    local DOMAIN_IP=$(nslookup "$LE_DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -v ':' | tail -n1)

    if [ -z "$DOMAIN_IP" ]; then
        echo -e "  ${C_ERR}Ошибка: Домен $LE_DOMAIN не резолвится (нет A-записи).${C_BASE}"
        return 1
    fi

    echo -e "  ${C_WHITE}IP сервера:${C_BASE} $SERVER_IP"
    echo -e "  ${C_WHITE}IP домена:${C_BASE}  $DOMAIN_IP"

    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo -e "  ${C_ERR}Внимание: IP не совпадают! Выпуск сертификата скорее всего завершится ошибкой.${C_BASE}"
        cursor_on
        read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Всё равно продолжить установку? (y/n): ${C_BASE}")" force_cont
        cursor_off
        if [[ ! "$force_cont" =~ ^[YyДд] ]]; then 
            echo -e "\n  ${C_DIM}Отмена. Возврат в меню.${C_BASE}"
            return 1
        fi
    else
        echo -e "  ${C_OK}IP совпадают. Продолжаем...${C_BASE}"
    fi
    export LE_DOMAIN
    
    echo ""
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Email: ${C_BASE}")" LE_EMAIL
    cursor_off
    if [ -z "$LE_EMAIL" ]; then return 1; fi
    export LE_EMAIL
    
    echo ""
    wait_for_apt
    run_module_task "УСТАНОВКА SSL" "Установка certbot..." "_do_certbot_install"
    
    # Останавливаем веб-серверы, чтобы порт 80 был свободен для certbot standalone
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    
    run_module_task "УСТАНОВКА SSL" "Выпуск сертификата ($LE_DOMAIN)..." "_do_certbot_run"
    
    if [ -d "/etc/letsencrypt/live/$LE_DOMAIN" ]; then
        # Проверяем, чтобы не записать дубль в базу
        if ! grep -q "^${LE_DOMAIN}|" /etc/aio_certs.db 2>/dev/null; then
            echo "$LE_DOMAIN|$(date +%s)" >> /etc/aio_certs.db
        fi
        echo -e "\n  ${C_OK}Сертификат для ${C_WHITE}${LE_DOMAIN}${C_OK} успешно получен.${C_BASE}\n"
        echo -e "  ${C_WHITE}Путь к сертификату: /etc/letsencrypt/live/${LE_DOMAIN}/fullchain.pem${C_BASE}"
        echo -e "  ${C_WHITE}Путь к ключу:       /etc/letsencrypt/live/${LE_DOMAIN}/privkey.pem${C_BASE}"
    else
        echo -e "\n  ${C_ERR}Не удалось получить сертификат. Проверь логи: $LOG_FILE${C_BASE}"
    fi
    
    # Запускаем службы обратно
    systemctl start nginx apache2 x-ui 2>/dev/null || true
}

_do_cert_renew() {
    systemctl stop nginx apache2 x-ui 2>/dev/null || true
    certbot renew --quiet
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
        
        # Динамически подгружаем список доменов как некликабельные заголовки
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
            2) return 1 ;; # Выход без паузы
        esac
    done
}
