#!/bin/bash
#############################################
# Sing-box Uninstallation Script
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
SERVICE_NAME="sing-box"
SCRIPT_PATH="/usr/bin/sbctl"

# Check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

# Check if systemd is available
check_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}Error: This script requires systemd to manage services!${PLAIN}"
        exit 1
    fi
}

# Check if sing-box service is running
check_service() {
    echo -e "${BLUE}Checking if sing-box service is running...${PLAIN}"
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${YELLOW}Sing-box service is running. Stopping service...${PLAIN}"
        systemctl stop ${SERVICE_NAME}
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Sing-box service stopped successfully!${PLAIN}"
        else
            echo -e "${RED}Failed to stop sing-box service!${PLAIN}"
            exit 1
        fi
    else
        echo -e "${GREEN}Sing-box service is not running.${PLAIN}"
    fi
}

# Disable and remove services
remove_services() {
    echo -e "${BLUE}Disabling and removing services...${PLAIN}"
    
    # Disable and stop sing-box service
    systemctl disable ${SERVICE_NAME} 2>/dev/null
    systemctl stop ${SERVICE_NAME} 2>/dev/null
    
    # Disable and stop subscription timer
    systemctl disable sing-box-subscription.timer 2>/dev/null
    systemctl stop sing-box-subscription.timer 2>/dev/null
    
    # Remove service files
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f /etc/systemd/system/sing-box-subscription.service
    rm -f /etc/systemd/system/sing-box-subscription.timer
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    echo -e "${GREEN}Services removed successfully!${PLAIN}"
}

# Remove sing-box files
remove_files() {
    echo -e "${BLUE}Removing sing-box files...${PLAIN}"
    
    # Remove binary and directories
    rm -rf ${SING_BOX_DIR}
    rm -f ${SCRIPT_PATH}
    rm -f /etc/logrotate.d/sing-box
    
    echo -e "${GREEN}Sing-box files removed successfully!${PLAIN}"
}

# Remove configuration files
remove_config() {
    echo -e "${YELLOW}Do you want to remove all configuration files? (y/n): ${PLAIN}"
    read -r confirm
    
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        echo -e "${BLUE}Removing configuration files...${PLAIN}"
        rm -rf ${CONFIG_DIR}
        rm -rf ${LOG_DIR}
        echo -e "${GREEN}Configuration files removed successfully!${PLAIN}"
    else
        echo -e "${YELLOW}Configuration files kept at ${CONFIG_DIR} and ${LOG_DIR}${PLAIN}"
    fi
}

# Main function
main() {
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│       Sing-box Uninstallation           │${PLAIN}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
    
    # Check if user is root
    check_root
    
    # Check if systemd is available
    check_systemd
    
    # Check if service is running and stop it
    check_service
    
    # Confirm uninstallation
    echo -e "${YELLOW}Are you sure you want to uninstall sing-box? (y/n): ${PLAIN}"
    read -r confirm
    
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${GREEN}Uninstallation cancelled!${PLAIN}"
        exit 0
    fi
    
    # Disable and remove services
    remove_services
    
    # Remove sing-box files
    remove_files
    
    # Remove configuration files
    remove_config
    
    echo -e "${GREEN}┌─────────────────────────────────────────┐${PLAIN}"
    echo -e "${GREEN}│    Sing-box uninstalled successfully!   │${PLAIN}"
    echo -e "${GREEN}└─────────────────────────────────────────┘${PLAIN}"
}

# Execute main function
main
