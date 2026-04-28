_do_prepare() {
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    apt-get update -y
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl gpg build-essential libdw-dev dkms ethtool fail2ban ufw irqbalance bc lsb-release dnsutils nano iproute2 jq
}

step_prepare() {
    echo -e "\n${C_ACCENT}[ 01 ] ПОДГОТОВКА СИСТЕМЫ${C_BASE}\n"
    wait_for_apt
    run_task "Подготовка системы" "_do_prepare"
}

_do_xanmod_repo() {
    SUPPORT=$(/lib64/ld-linux-x86-64.so.2 --help)
    if echo "$SUPPORT" | grep -q "x86-64-v4 (supported"; then PACKAGE="linux-xanmod-edge-x64v4"
    elif echo "$SUPPORT" | grep -q "x86-64-v3 (supported"; then PACKAGE="linux-xanmod-edge-x64v3"
    elif echo "$SUPPORT" | grep -q "x86-64-v2 (supported"; then PACKAGE="linux-xanmod-edge-x64v2"
    else PACKAGE="linux-xanmod-lts-x64v1"; fi
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
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
    echo -e "\n${C_ACCENT}[ 02 ] ЯДРО XANMOD${C_BASE}\n"
    if check_installed "uname -r | grep -qi xanmod || dpkg -l | grep -qi linux-image.*xanmod"; then return; fi
    run_task "Конфигурация репозитория" "_do_xanmod_repo"
    wait_for_apt
    run_task "Установка XanMod (это реально долго...)" "_do_xanmod_install"
}

_do_bbr() {
    cat <<EON | tee /etc/sysctl.conf > /dev/null
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EON
    sysctl -p
}

step_network() {
    echo -e "\n${C_ACCENT}[ 03 ] BBR & TCP${C_BASE}\n"
    run_task "TCP Optimization" "_do_bbr"
}

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
        case $MENU_CHOICE in
            0) SWAP_SIZE="0.5"; SWAP_MB=512; break ;;
            1) SWAP_SIZE="1"; SWAP_MB=1024; break ;;
            2) SWAP_SIZE="1.5"; SWAP_MB=1536; break ;;
            3) SWAP_SIZE="2"; SWAP_MB=2048; break ;;
            4) clear; run_task "Удаление Swap" "_remove_swap"; return 0 ;;
            5) return 1 ;;
        esac
    done
    clear
    echo -e "\n${C_ACCENT}[ 04 ] НАСТРОЙКА ФАЙЛА ПОДКАЧКИ${C_BASE}\n"
    export SWAP_MB
    run_task "Создание /swapfile (${SWAP_SIZE}G)" "_do_swap"
}

_do_disable_ipv6() {
    cat <<EON | tee /etc/sysctl.d/99-unswitch-noipv6.conf > /dev/null
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EON
    sysctl --system > /dev/null
}

_do_enable_ipv6() {
    rm -f /etc/sysctl.d/99-unswitch-noipv6.conf 
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null 
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 > /dev/null 
    sysctl --system > /dev/null
}

step_ipv6() {
    local opts=("Отключить IPv6" "Включить IPv6" "Назад")
    while true; do
        render_menu "УПРАВЛЕНИЕ IPv6" "${opts[@]}"
        clear
        case $MENU_CHOICE in
            0) run_task "Отключение IPv6 в ядре" "_do_disable_ipv6"; return 0 ;;
            1) run_task "Включение IPv6 в ядре" "_do_enable_ipv6"; return 0 ;;
            2) return 1 ;;
        esac
    done
}
