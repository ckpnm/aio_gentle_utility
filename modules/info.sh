_do_speedtest_cli() {
    mkdir -p /tmp/st && cd /tmp/st
    wget -qO st.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
    tar -xf st.tgz
}

step_speedtest() {
    echo -e "\n${C_ACCENT}[ 10 ] ЗАМЕР СКОРОСТИ (OOKLA)${C_BASE}\n"
    run_task "Speedtest CLI" "_do_speedtest_cli"
    
    yes "YES" | /tmp/st/speedtest --accept-license --accept-gdpr > /tmp/st/result.log 2>&1 &
    local st_pid=$!
    local task_name="Выполняется замер скорости..."
    printf "\r  ${C_ACCENT}${C_BOLD}%s${C_BASE} " "$task_name"
    printf "\e[s"
    
    _draw_progress "$st_pid" &
    local bar_pid=$!
    wait $st_pid
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    printf "\r\e[K"
    
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' /tmp/st/result.log > /tmp/st/clean.log
    local dl=$(grep "Download:" /tmp/st/clean.log | awk '{print $2" "$3}')
    if [ -z "$dl" ]; then
        echo -e "  ${C_ERR}[ОШИБКА] Не удалось выполнить замер.${C_BASE}\n"
    else
        echo -e "  ${C_ACCENT}Локация:  ${C_BASE} $(grep "Server:" /tmp/st/clean.log | cut -d: -f2- | xargs)"
        echo -e "  ${C_ACCENT}Провайдер:${C_BASE} $(grep "ISP:" /tmp/st/clean.log | cut -d: -f2- | xargs)"
        echo -e "  ${C_ACCENT}Ping:     ${C_BASE} $(grep -i "latency:" /tmp/st/clean.log | awk '{print $3" "$4}')"
        echo -e "  ${C_ACCENT}Download: ${C_BASE} $dl"
        echo -e "  ${C_ACCENT}Upload:   ${C_BASE} $(grep "Upload:" /tmp/st/clean.log | awk '{print $2" "$3}')"
    fi
    rm -rf /tmp/st
}

step_ipregion() {
    echo -e "\n${C_ACCENT}[ 11 ] IP REGION CHECK${C_BASE}\n"
    local ip_tmp="/tmp/ipregion.log"
    bash <(wget -qO- https://github.com/Davoyan/ipregion/raw/main/ipregion.sh) > "$ip_tmp" 2>/dev/null &
    local task_pid=$!
    printf "\r  ${C_ACCENT}${C_BOLD}Получение гео-данных...${C_BASE} \e[s"
    _draw_progress "$task_pid" &
    local bar_pid=$!
    wait $task_pid
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    printf "\r\e[K\n"
    
    if [ -f "$ip_tmp" ]; then
        sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$ip_tmp" | while IFS= read -r line; do
            [[ -z "${line// /}" ]] && continue
            [[ "$line" == *"https://github.com/Davoyan/ipregion"* ]] && continue
            
            if [[ "$line" == *"Forked by"* ]]; then continue; fi

            if [[ "$line" =~ ^Legend ]]; then
                echo ""
                echo -e "  ${C_ACCENT}${C_BOLD}${line}${C_BASE}"
                echo ""
                continue
            fi

            if [[ "$line" =~ ^Service[[:space:]]+IPv4 ]] || [[ "$line" =~ ^Code[[:space:]]+Country ]]; then
                line="${line//\% /}"
                echo -e "  ${C_ACCENT}${C_BOLD}${line}${C_BASE}"
                continue
            fi
            
            local add_newlines=0
            if [[ "$line" =~ ^2ip\.io ]]; then add_newlines=1; fi
            
            if [[ "$line" =~ ^([A-Za-z/]+)[[:space:]]+([A-Za-z\ ]+)[[:space:]]+([0-9]+)%$ ]]; then
                local code="${BASH_REMATCH[1]}"
                local country="${BASH_REMATCH[2]}"
                local pct="${BASH_REMATCH[3]}"
                
                local p_code=$(printf "%-7s" "$code")
                local p_country=$(printf "%-14s" "$country")
                echo -e "  ${C_ACCENT}${p_code}${C_WHITE}${p_country}${C_WHITE}${pct} %${C_BASE}"
                continue
            fi
            
            if [[ "$line" =~ ^([^:]+):\ (.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                echo -e "  ${C_ACCENT}${key}:${C_BASE} ${C_WHITE}${val}${C_BASE}"
            else
                local left=$(printf "%-21s" "${line:0:21}")
                local right="${line:21}"
                
                right="${right//Yes/${C_OK}Yes${C_WHITE}}"
                right="${right//No/${C_ERR}No${C_WHITE}}"
                right="${right//N\/A/${C_ERR}N\/A${C_WHITE}}"
                
                echo -e "  ${C_ACCENT}${left}${C_WHITE}${right}${C_BASE}"
            fi

            if [[ $add_newlines -eq 1 ]]; then echo ""; echo ""; fi
        done
        rm -f "$ip_tmp"
    fi
}

_do_logs() {
    journalctl --vacuum-time=1d
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} +
}

step_logs() {
    echo -e "\n${C_ACCENT}[ 12 ] ОЧИСТКА И РОТАЦИЯ ЛОГОВ${C_BASE}\n"
    run_task "Очистка системных журналов" "_do_logs"
    echo -e "\n  ${C_OK}Место на диске успешно освобождено.${C_BASE}"
}

step_bypass_whitelist() {
    clear
    echo -e "${C_ACCENT}"
cat << 'EOF'
⡴⠒⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠉⠳⡆⠀
⣇⠰⠉⢙⡄⠀⠀⣴⠖⢦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣆⠁⠙⡆
⠘⡇⢠⠞⠉⠙⣾⠃⢀⡼⠀⠀⠀⠀⠀⠀⠀⢀⣼⡀⠄⢷⣄⣀⠀⠀⠀⠀⠀⠀⠀⠰⠒⠲⡄⠀⣏⣆⣀⡍
⠀⢠⡏⠀⡤⠒⠃⠀⡜⠀⠀⠀⠀⠀⢀⣴⠾⠛⡁⠀⠀⢀⣈⡉⠙⠳⣤⡀⠀⠀⠀⠘⣆⠀⣇⡼⢋⠀⠀⢱
⠀⠘⣇⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⡴⢋⡣⠊⡩⠋⠀⠀⠀⠣⡉⠲⣄⠀⠙⢆⠀⠀⠀⣸⠀⢉⠀⢀⠿⠀⢸
⠀⠀⠸⡄⠀⠈⢳⣄⡇⠀⠀⢀⡞⠀⠈⠀⢀⣴⣾⣿⣿⣿⣿⣦⡀⠀⠀⠀⠈⢧⠀⠀⢳⣰⠁⠀⠀⠀⣠⠃
⠀⠀⠀⠘⢄⣀⣸⠃⠀⠀⠀⡸⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣆⠀⠀⠀⠈⣇⠀⠀⠙⢄⣀⠤⠚⠁⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡄⠀⠀⠀⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀⠀⠀⢘⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⢰⣿⣿⣿⡿⠛⠁⠀⠉⠛⢿⣿⣿⣿⣧⠀⠀⣼⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡀⣸⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣿⡀⢀⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡇⠹⠿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⡿⠁⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⣤⣞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢢⣀⣠⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠲⢤⣀⣀⠀⢀⣀⣀⠤⠒⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
EOF
    echo -e "${C_BASE}"
    echo -e "\n  ${C_ERR}${C_BOLD}НЕ ОБОЙДЕШЬ!${C_BASE}\n"
}
