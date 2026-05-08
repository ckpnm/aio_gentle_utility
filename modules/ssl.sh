# ==============================================================================
# МОДУЛЬ: SSL СЕРТИФИКАТЫ
# ==============================================================================

_do_certbot_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" certbot
}

_do_certbot_run() {
    certbot certonly --standalone --agree-tos -m "$LE_EMAIL" -d "$LE_DOMAIN" --non-interactive
}

_do_dns_check() {
    SERVER_IP=$(curl -s4 ifconfig.me)
    DOMAIN_IP=$(nslookup "$LE_DOMAIN" | grep -iE 'Address: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -n1 | awk '{print $2}')
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo "Ошибка: IP сервера ($SERVER_IP) не совпадает с IP домена ($DOMAIN_IP)" >&2
        exit 1
    fi
}

_install_cert() {
    clear
    draw_module_header "УСТАНОВКА SSL"
    echo ""
    
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Домен (например, domain.com): ${C_BASE}")" LE_DOMAIN
    if [ -z "$LE_DOMAIN" ]; then cursor_off; return; fi
    
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Домен точно привязан к IP этого сервера? (y/n): ${C_BASE}")" CONFIRM_IP
    if [[ ! "$CONFIRM_IP" =~ ^[YyДд] ]]; then 
        echo -e "\n  ${C_DIM}Отмена. Возврат в меню.${C_BASE}"
        cursor_off; sleep 1; return 1
    fi
    export LE_DOMAIN
    cursor_off
    
    echo ""
    run_module_task "УСТАНОВКА SSL" "Проверка DNS (nslookup)..." "_do_dns_check"
    if [ $? -ne 0 ]; then return; fi
    
    echo ""
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Email: ${C_BASE}")" LE_EMAIL
    cursor_off
    if [ -z "$LE_EMAIL" ]; then return; fi
    export LE_EMAIL
    
    echo ""
    wait_for_apt
    run_module_task "УСТАНОВКА SSL" "Установка certbot..." "_do_certbot_install"
    run_module_task "УСТАНОВКА SSL" "Выпуск сертификата ($LE_DOMAIN)..." "_do_certbot_run"
    
    if [ -d "/etc/letsencrypt/live/$LE_DOMAIN" ]; then
        # Проверяем, чтобы не записать дубль в базу
        if ! grep -q "^${LE_DOMAIN}|" /etc/aio_certs.db 2>/dev/null; then
            echo "$LE_DOMAIN|$(date +%s)" >> /etc/aio_certs.db
        fi
        echo -e "\n  ${C_OK}Сертификат для ${C_WHITE}${LE_DOMAIN}${C_OK} получен.${C_BASE}\n"
        echo -e "  ${C_WHITE}Путь к сертификату: /etc/letsencrypt/live/${LE_DOMAIN}/fullchain.pem${C_BASE}"
        echo -e "  ${C_WHITE}Путь к ключу:       /etc/letsencrypt/live/${LE_DOMAIN}/privkey.pem${C_BASE}"
    fi
}

_do_cert_renew() {
    certbot renew --quiet
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
