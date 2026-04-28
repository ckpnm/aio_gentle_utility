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
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then exit 1; fi
}

_install_cert() {
    echo -e "\n${C_ACCENT}[ SSL ] УСТАНОВКА${C_BASE}\n"
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Домен (например, domain.com): ${C_BASE}")" LE_DOMAIN
    if [ -z "$LE_DOMAIN" ]; then cursor_off; return; fi
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Домен точно привязан к IP этого сервера? (y/n): ${C_BASE}")" CONFIRM_IP
    if [[ ! "$CONFIRM_IP" =~ ^[YyДд] ]]; then cursor_off; return 1; fi
    export LE_DOMAIN
    cursor_off
    run_task "Проверка DNS (nslookup)" "_do_dns_check"
    if [ $? -ne 0 ]; then return; fi
    cursor_on
    read -p "$(echo -e "  ${C_ACCENT}${C_BOLD}> Email: ${C_BASE}")" LE_EMAIL
    cursor_off
    if [ -z "$LE_EMAIL" ]; then return; fi
    export LE_EMAIL
    
    wait_for_apt
    run_task "Установка certbot" "_do_certbot_install"
    run_task "Выпуск сертификата ($LE_DOMAIN)" "_do_certbot_run"
    
    if [ -d "/etc/letsencrypt/live/$LE_DOMAIN" ]; then
        echo "$LE_DOMAIN|$(date +%s)" >> /etc/aio_certs.db
        echo -e "\n  ${C_OK}Сертификат для ${C_WHITE}${LE_DOMAIN}${C_OK} получен.${C_BASE}"
    fi
}

_do_cert_renew() { certbot renew --quiet; }

_renew_cert() {
    echo -e "\n${C_ACCENT}[ SSL ] ОБНОВЛЕНИЕ${C_BASE}\n"
    if [ ! -f /etc/aio_certs.db ]; then return; fi
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
    run_task "Обновление сертификатов" "_do_cert_renew"
}

step_letsencrypt() {
    local opts=("Установить сертификат" "Обновить сертификат" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ SSL СЕРТИФИКАТАМИ" "${opts[@]}"
        local local_choice=$MENU_CHOICE
        clear
        case $local_choice in
            0) _install_cert; return 0 ;;
            1) _renew_cert; return 0 ;;
            2) return 1 ;;
        esac
    done
}
