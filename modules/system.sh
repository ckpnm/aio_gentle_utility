# ==============================================================================
# МОДУЛЬ: БАЗОВЫЕ СИСТЕМНЫЕ НАСТРОЙКИ (XanMod, BBR, Swap, Логи)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. ЯДРО XANMOD
# ------------------------------------------------------------------------------
_do_xanmod_repo() {
    SUPPORT=$(/lib64/ld-linux-x86-64.so.2 --help)
    if echo "$SUPPORT" | grep -q "x86-64-v4 (supported"; then PACKAGE="linux-xanmod-edge-x64v4"
    elif echo "$SUPPORT" | grep -q "x86-64-v3 (supported"; then PACKAGE="linux-xanmod-edge-x64v3"
    elif echo "$SUPPORT" | grep -q "x86-64-v2 (supported"; then PACKAGE="linux-xanmod-edge-x64v2"
    else PACKAGE="linux-xanmod-lts-x64v1"; fi
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] https://deb.xanmod.org $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
}

_do_xanmod_install() {
    SUPPORT=$(/lib64/ld-linux-x86-64.so.2 --help)
    if echo "$SUPPORT" | grep -q "x86-64-v4 (supported"; then PACKAGE="linux-xanmod-edge-x64v4"
    elif echo "$SUPPORT" | grep -q "x86-64-v3 (supported"; then PACKAGE="linux-xanmod-edge-x64v3"
    elif echo "$SUPPORT" | grep -q "x86-64-v2 (supported"; then PACKAGE="linux-xanmod-edge-x64v2"
    else PACKAGE="linux-xanmod-lts-x64v1"; fi
    
    export DEBIAN_FRONTEND=noninteractive 
    apt-get update -y -qq 
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $PACKAGE
    update-grub
}

step_kernel() {
    echo -e "\n${C_ACCENT}[ БАЗА ] ЯДРО XANMOD${C_BASE}\n"
    if check_installed "uname -r | grep -qi xanmod || dpkg -l | grep -qi linux-image.*xanmod"; then return; fi
    
    run_task "Конфигурация репозитория" "_do_xanmod_repo"
    wait_for_apt
    run_task "Установка XanMod (это реально долго...)" "_do_xanmod_install"
}

# ------------------------------------------------------------------------------
# 2. СЕТЕВЫЕ ОПТИМИЗАЦИИ (BBR & TCP)
# ------------------------------------------------------------------------------
_do_bbr() {
    
    sed -i '/net.ipv4.tcp_congestion_control = bbr/d' /etc/sysctl.conf
    sed -i '/net.core.default_qdisc = fq/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf

    cat <<EON >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EON
    sysctl -p > /dev/null
}

step_network() {
    echo -e "\n${C_ACCENT}[ БАЗА ] ОПТИМИЗАЦИЯ СЕТИ (BBR & TCP)${C_BASE}\n"
    run_task "Применение TCP BBR" "_do_bbr"
}

# ------------------------------------------------------------------------------
# 3. ФАЙЛ ПОДКАЧКИ (SWAP)
# ------------------------------------------------------------------------------
_remove_swap() {
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
}

_do_swap() {
    _remove_swap
    fallocate -l ${SWAP_MB}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_MB}
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

step_swap() {
    local current_swap="Не настроен"
    if [ -f /swapfile ] || [ "$(swapon --show)" ]; then
        current_swap=$(swapon --show=SIZE --noheadings | head -n1)
        [ -z "$current_swap" ] && current_swap="Неизвестно"
    fi
    
    local opts=("0.5 ГБ" "1 ГБ" "1.5 ГБ" "2 ГБ" "Удалить Swap" "Назад")
    while true; do
        render_menu "SWAP | ТЕКУЩИЙ: ${current_swap}" "${opts[@]}"
        local local_choice=$MENU_CHOICE
        case $local_choice in
            0) SWAP_SIZE="0.5"; SWAP_MB=512; break ;;
            1) SWAP_SIZE="1"; SWAP_MB=1024; break ;;
            2) SWAP_SIZE="1.5"; SWAP_MB=1536; break ;;
            3) SWAP_SIZE="2"; SWAP_MB=2048; break ;;
            4) 
                clear
                echo -e "\n${C_ACCENT}[ SWAP ] УДАЛЕНИЕ ФАЙЛА ПОДКАЧКИ${C_BASE}\n"
                run_task "Удаление Swap" "_remove_swap"
                return 0
                ;;
            5) return 1 ;;
        esac
    done
    
    clear
    echo -e "\n${C_ACCENT}[ SWAP ] НАСТРОЙКА ФАЙЛА ПОДКАЧКИ${C_BASE}\n"
    export SWAP_MB
    run_task "Создание /swapfile (${SWAP_SIZE}G)" "_do_swap"
    return 0
}

# ------------------------------------------------------------------------------
# 4. ОЧИСТКА И РОТАЦИЯ ЛОГОВ
# ------------------------------------------------------------------------------
_do_logs() {
    journalctl --vacuum-time=1d >/dev/null 2>&1
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} +
    if command -v docker >/dev/null 2>&1; then
        find /var/lib/docker/containers/ -type f -name "*-json.log" -exec truncate -s 0 {} +
    fi
}

step_logs() {
    echo -e "\n${C_ACCENT}[ БАЗА ] ОЧИСТКА И РОТАЦИЯ ЛОГОВ${C_BASE}\n"
    run_task "Очистка системных журналов" "_do_logs"
    echo -e "\n  ${C_OK}Готово! Место на диске успешно освобождено.${C_BASE}"
}
