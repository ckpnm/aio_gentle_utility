#!/bin/bash

# Замени на URL своего репозитория!
REPO_URL="https://github.com/ckpnm/aio_gentle.git"
INSTALL_DIR="/opt/aio_gentle"

if [[ $EUID -ne 0 ]]; then
   echo -e "\e[1;31mОшибка: Скрипт должен быть запущен от имени root.\e[0m"
   exit 1
fi

echo -e "\e[1;36mУстановка AIO VPN GENTLE UTILITY...\e[0m"

apt-get update -qq && apt-get install -y -qq git curl jq

if [ -d "$INSTALL_DIR" ]; then
    echo -e "\e[90mОбновление существующей установки...\e[0m"
    cd "$INSTALL_DIR" && git pull origin main >/dev/null 2>&1
else
    echo -e "\e[90mКлонирование репозитория...\e[0m"
    git clone "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
fi

chmod +x "$INSTALL_DIR/main.sh"
ln -sf "$INSTALL_DIR/main.sh" /usr/local/bin/aio_gentle

echo -e "\e[32m[ ИНФО ] Утилита установлена! Введи команду: \e[1m\e[97maio_gentle\e[0m"
