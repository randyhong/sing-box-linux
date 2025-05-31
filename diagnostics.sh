#!/bin/bash
#############################################
# Sing-box Diagnostics Module
# Author: Cascade AI
# Version: 1.0.0
# Date: 2025-05-31
#############################################

# Color definitions
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# Configuration paths
SING_BOX_DIR="/usr/local/sing-box"
CONFIG_DIR="/etc/sing-box"
LOG_DIR="/var/log/sing-box"

# Check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

# Check system information
check_system_info() {
    echo -e "${BLUE}System Information:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    # OS Information
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "${BLUE}│${PLAIN} OS: ${GREEN}${PRETTY_NAME}${PLAIN}"
    else
        echo -e "${BLUE}│${PLAIN} OS: ${YELLOW}Unknown${PLAIN}"
    fi
    
    # Kernel Information
    echo -e "${BLUE}│${PLAIN} Kernel: ${GREEN}$(uname -r)${PLAIN}"
    
    # Architecture
    echo -e "${BLUE}│${PLAIN} Architecture: ${GREEN}$(uname -m)${PLAIN}"
    
    # CPU Information
    cpu_info=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d':' -f2 | sed 's/^[ \t]*//')
    cpu_cores=$(grep -c "processor" /proc/cpuinfo)
    echo -e "${BLUE}│${PLAIN} CPU: ${GREEN}${cpu_info} (${cpu_cores} cores)${PLAIN}"
    
    # Memory Information
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    mem_used=$(free -m | awk '/Mem:/ {print $3}')
    mem_usage=$((mem_used * 100 / mem_total))
    echo -e "${BLUE}│${PLAIN} Memory: ${GREEN}${mem_used}MB / ${mem_total}MB (${mem_usage}%)${PLAIN}"
    
    # Disk Information
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    disk_used=$(df -h / | awk 'NR==2 {print $3}')
    disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    echo -e "${BLUE}│${PLAIN} Disk: ${GREEN}${disk_used} / ${disk_total} (${disk_usage})${PLAIN}"
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Check sing-box installation
check_sing_box() {
    echo -e "${BLUE}Sing-box Installation:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    # Check binary
    if [[ -f "${SING_BOX_DIR}/sing-box" ]]; then
        version=$(${SING_BOX_DIR}/sing-box version | head -n 1)
        echo -e "${BLUE}│${PLAIN} Binary: ${GREEN}${version}${PLAIN}"
    else
        echo -e "${BLUE}│${PLAIN} Binary: ${RED}Not installed${PLAIN}"
    fi
    
    # Check configuration
    if [[ -f "${CONFIG_DIR}/config.json" ]]; then
        config_size=$(du -h "${CONFIG_DIR}/config.json" | cut -f1)
        echo -e "${BLUE}│${PLAIN} Configuration: ${GREEN}Found (${config_size})${PLAIN}"
        
        # Check configuration syntax
        if ${SING_BOX_DIR}/sing-box check -C ${CONFIG_DIR}/config.json >/dev/null 2>&1; then
            echo -e "${BLUE}│${PLAIN} Config Syntax: ${GREEN}Valid${PLAIN}"
        else
            echo -e "${BLUE}│${PLAIN} Config Syntax: ${RED}Invalid${PLAIN}"
        fi
    else
        echo -e "${BLUE}│${PLAIN} Configuration: ${RED}Not found${PLAIN}"
    fi
    
    # Check service
    if systemctl is-active --quiet sing-box; then
        echo -e "${BLUE}│${PLAIN} Service: ${GREEN}Running${PLAIN}"
    else
        echo -e "${BLUE}│${PLAIN} Service: ${RED}Not running${PLAIN}"
    fi
    
    # Check logs
    if [[ -d "${LOG_DIR}" ]]; then
        log_count=$(find "${LOG_DIR}" -type f | wc -l)
        echo -e "${BLUE}│${PLAIN} Logs: ${GREEN}${log_count} files found${PLAIN}"
    else
        echo -e "${BLUE}│${PLAIN} Logs: ${RED}Directory not found${PLAIN}"
    fi
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Check network connectivity
check_network() {
    echo -e "${BLUE}Network Connectivity:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    # Check DNS resolution
    echo -e "${BLUE}│${PLAIN} DNS Resolution:${PLAIN}"
    for domain in "google.com" "cloudflare.com" "baidu.com"; do
        if host "${domain}" >/dev/null 2>&1; then
            echo -e "${BLUE}│${PLAIN}   - ${domain}: ${GREEN}OK${PLAIN}"
        else
            echo -e "${BLUE}│${PLAIN}   - ${domain}: ${RED}Failed${PLAIN}"
        fi
    done
    
    # Check ICMP connectivity
    echo -e "${BLUE}│${PLAIN} ICMP Connectivity:${PLAIN}"
    for ip in "1.1.1.1" "8.8.8.8" "223.5.5.5"; do
        if ping -c 1 -W 2 "${ip}" >/dev/null 2>&1; then
            echo -e "${BLUE}│${PLAIN}   - ${ip}: ${GREEN}OK${PLAIN}"
        else
            echo -e "${BLUE}│${PLAIN}   - ${ip}: ${RED}Failed${PLAIN}"
        fi
    done
    
    # Check HTTP connectivity
    echo -e "${BLUE}│${PLAIN} HTTP Connectivity:${PLAIN}"
    for url in "https://www.google.com" "https://www.cloudflare.com" "https://www.baidu.com"; do
        if curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" "${url}" | grep -q "200\|301\|302"; then
            echo -e "${BLUE}│${PLAIN}   - ${url}: ${GREEN}OK${PLAIN}"
        else
            echo -e "${BLUE}│${PLAIN}   - ${url}: ${RED}Failed${PLAIN}"
        fi
    done
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Run traceroute
run_traceroute() {
    local target="$1"
    
    if [[ -z "${target}" ]]; then
        target="1.1.1.1"
    fi
    
    echo -e "${BLUE}Traceroute to ${target}:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    if command -v traceroute >/dev/null 2>&1; then
        traceroute -m 15 "${target}"
    else
        echo -e "${BLUE}│${PLAIN} ${RED}traceroute command not found!${PLAIN}"
    fi
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Run speed test
run_speed_test() {
    echo -e "${BLUE}Speed Test:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    if command -v curl >/dev/null 2>&1; then
        # Download test
        echo -e "${BLUE}│${PLAIN} Download Speed Test:${PLAIN}"
        for url in "https://speed.cloudflare.com/__down?bytes=10000000" "https://cachefly.cachefly.net/10mb.test"; do
            echo -e "${BLUE}│${PLAIN}   - Testing ${url}...${PLAIN}"
            result=$(curl -s -w "%{speed_download}" -o /dev/null "${url}")
            speed=$(echo "${result} / 1024 / 1024 * 8" | bc -l)
            echo -e "${BLUE}│${PLAIN}     Speed: ${GREEN}$(printf "%.2f" ${speed}) Mbps${PLAIN}"
        done
    else
        echo -e "${BLUE}│${PLAIN} ${RED}curl command not found!${PLAIN}"
    fi
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Check open ports
check_ports() {
    echo -e "${BLUE}Open Ports:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    
    if command -v ss >/dev/null 2>&1; then
        echo -e "${BLUE}│${PLAIN} Listening TCP Ports:${PLAIN}"
        ss -tuln | grep LISTEN | sort -n -k 5 | while read -r line; do
            echo -e "${BLUE}│${PLAIN}   ${line}${PLAIN}"
        done
    elif command -v netstat >/dev/null 2>&1; then
        echo -e "${BLUE}│${PLAIN} Listening TCP Ports:${PLAIN}"
        netstat -tuln | grep LISTEN | sort -n -k 4 | while read -r line; do
            echo -e "${BLUE}│${PLAIN}   ${line}${PLAIN}"
        done
    else
        echo -e "${BLUE}│${PLAIN} ${RED}ss/netstat command not found!${PLAIN}"
    fi
    
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
}

# Show diagnostics menu
show_diagnostics_menu() {
    clear
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│         Network Diagnostics Menu        │${PLAIN}"
    echo -e "${BLUE}├─────────────────────────────────────────┤${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}1.${PLAIN} System Information                 ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}2.${PLAIN} Sing-box Installation Check        ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}3.${PLAIN} Network Connectivity Test          ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}4.${PLAIN} Traceroute                         ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}5.${PLAIN} Speed Test                         ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}6.${PLAIN} Check Open Ports                   ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}7.${PLAIN} Run All Tests                      ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}0.${PLAIN} Back to main menu                  ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
    echo ""
    read -p "Please enter your choice [0-7]: " choice
    
    case "${choice}" in
        1)
            check_system_info
            ;;
        2)
            check_sing_box
            ;;
        3)
            check_network
            ;;
        4)
            read -p "Enter target host (default: 1.1.1.1): " target
            run_traceroute "${target}"
            ;;
        5)
            run_speed_test
            ;;
        6)
            check_ports
            ;;
        7)
            check_system_info
            check_sing_box
            check_network
            run_traceroute "1.1.1.1"
            run_speed_test
            check_ports
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${PLAIN}"
            sleep 2
            show_diagnostics_menu
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to the diagnostics menu..." dummy
    show_diagnostics_menu
}

# Run diagnostics
run_diagnostics() {
    check_root
    
    if [[ $# -lt 2 ]]; then
        show_diagnostics_menu
        return 0
    fi
    
    case "$2" in
        system)
            check_system_info
            ;;
        singbox)
            check_sing_box
            ;;
        network)
            check_network
            ;;
        traceroute)
            run_traceroute "$3"
            ;;
        speed)
            run_speed_test
            ;;
        ports)
            check_ports
            ;;
        all)
            check_system_info
            check_sing_box
            check_network
            run_traceroute "1.1.1.1"
            run_speed_test
            check_ports
            ;;
        *)
            echo -e "${RED}Unknown command: $2${PLAIN}"
            echo -e "${YELLOW}Usage: sbctl test [system|singbox|network|traceroute|speed|ports|all]${PLAIN}"
            return 1
            ;;
    esac
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_diagnostics "$@"
fi
