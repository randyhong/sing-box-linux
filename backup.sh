#!/bin/bash
#############################################
# Sing-box Backup and Restore Module
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
CONFIG_DIR="/etc/sing-box"
BACKUP_DIR="${CONFIG_DIR}/backups"

# Check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

# Initialize backup directory
init_backup() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}"
    fi
}

# Create a backup
create_backup() {
    local name="$1"
    local timestamp=$(date +"%Y%m%d%H%M%S")
    
    if [[ -z "${name}" ]]; then
        name="backup_${timestamp}"
    fi
    
    local backup_file="${BACKUP_DIR}/${name}.tar.gz"
    
    echo -e "${BLUE}Creating backup: ${backup_file}...${PLAIN}"
    
    # Create tar archive
    tar -czf "${backup_file}" -C "${CONFIG_DIR}" . --exclude="backups"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Backup created successfully!${PLAIN}"
        echo -e "${GREEN}Backup file: ${backup_file}${PLAIN}"
    else
        echo -e "${RED}Failed to create backup!${PLAIN}"
        return 1
    fi
    
    # Clean up old backups (keep last 10)
    echo -e "${BLUE}Cleaning up old backups...${PLAIN}"
    ls -t "${BACKUP_DIR}"/*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null
}

# List available backups
list_backups() {
    local count=$(find "${BACKUP_DIR}" -name "*.tar.gz" | wc -l)
    
    if [[ "${count}" -eq 0 ]]; then
        echo -e "${YELLOW}No backups found!${PLAIN}"
        return 0
    fi
    
    echo -e "${BLUE}Available backups:${PLAIN}"
    echo -e "${BLUE}┌───────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│ ${PLAIN}Name                                │ Size     │ Date        ${BLUE}│${PLAIN}"
    echo -e "${BLUE}├───────────────────────────────────────────────────────────┤${PLAIN}"
    
    find "${BACKUP_DIR}" -name "*.tar.gz" -printf "%f\t%s\t%TY-%Tm-%Td\n" | sort -r | while IFS=$'\t' read -r name size date; do
        size_human=$(echo "${size}" | awk '{ suffix="BKMGT"; for(i=1; $1>1024 && i<length(suffix); i++) $1/=1024; printf "%.2f%s", $1, substr(suffix,i,1); }')
        printf "${BLUE}│${PLAIN} %-35s │ %-8s │ %-11s ${BLUE}│${PLAIN}\n" "${name}" "${size_human}" "${date}"
    done
    
    echo -e "${BLUE}└───────────────────────────────────────────────────────────┘${PLAIN}"
}

# Restore from backup
restore_backup() {
    local backup="$1"
    
    if [[ -z "${backup}" ]]; then
        echo -e "${RED}Error: Backup file is required!${PLAIN}"
        list_backups
        return 1
    fi
    
    # If backup doesn't have .tar.gz extension, add it
    if [[ ! "${backup}" =~ \.tar\.gz$ ]]; then
        backup="${backup}.tar.gz"
    fi
    
    local backup_file="${BACKUP_DIR}/${backup}"
    
    if [[ ! -f "${backup_file}" ]]; then
        echo -e "${RED}Error: Backup file not found: ${backup_file}${PLAIN}"
        list_backups
        return 1
    fi
    
    echo -e "${BLUE}Restoring from backup: ${backup_file}...${PLAIN}"
    
    # Create a backup of current configuration
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local temp_backup="${BACKUP_DIR}/pre_restore_${timestamp}.tar.gz"
    
    echo -e "${BLUE}Creating backup of current configuration...${PLAIN}"
    tar -czf "${temp_backup}" -C "${CONFIG_DIR}" . --exclude="backups"
    
    # Stop sing-box service
    echo -e "${BLUE}Stopping sing-box service...${PLAIN}"
    systemctl stop sing-box
    
    # Extract backup
    echo -e "${BLUE}Extracting backup...${PLAIN}"
    mkdir -p "${CONFIG_DIR}/tmp_restore"
    tar -xzf "${backup_file}" -C "${CONFIG_DIR}/tmp_restore"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to extract backup!${PLAIN}"
        echo -e "${YELLOW}Restoring previous configuration...${PLAIN}"
        tar -xzf "${temp_backup}" -C "${CONFIG_DIR}"
        systemctl start sing-box
        rm -rf "${CONFIG_DIR}/tmp_restore"
        return 1
    fi
    
    # Check configuration syntax
    echo -e "${BLUE}Checking configuration syntax...${PLAIN}"
    if [[ -f "/usr/local/sing-box/sing-box" && -f "${CONFIG_DIR}/tmp_restore/config.json" ]]; then
        if ! /usr/local/sing-box/sing-box check -C "${CONFIG_DIR}/tmp_restore/config.json"; then
            echo -e "${RED}Configuration syntax error!${PLAIN}"
            echo -e "${YELLOW}Do you want to continue anyway? (y/n): ${PLAIN}"
            read -r continue_restore
            
            if [[ "${continue_restore}" != "y" && "${continue_restore}" != "Y" ]]; then
                echo -e "${YELLOW}Restoring previous configuration...${PLAIN}"
                tar -xzf "${temp_backup}" -C "${CONFIG_DIR}"
                systemctl start sing-box
                rm -rf "${CONFIG_DIR}/tmp_restore"
                return 1
            fi
        fi
    fi
    
    # Copy files from tmp_restore to CONFIG_DIR
    echo -e "${BLUE}Applying restored configuration...${PLAIN}"
    find "${CONFIG_DIR}" -mindepth 1 -maxdepth 1 -not -path "${CONFIG_DIR}/backups" -not -path "${CONFIG_DIR}/tmp_restore" -exec rm -rf {} \;
    find "${CONFIG_DIR}/tmp_restore" -mindepth 1 -maxdepth 1 -exec cp -rf {} "${CONFIG_DIR}" \;
    rm -rf "${CONFIG_DIR}/tmp_restore"
    
    # Start sing-box service
    echo -e "${BLUE}Starting sing-box service...${PLAIN}"
    systemctl start sing-box
    
    echo -e "${GREEN}Restore completed successfully!${PLAIN}"
}

# Show backup menu
show_backup_menu() {
    clear
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│       Backup and Restore Menu           │${PLAIN}"
    echo -e "${BLUE}├─────────────────────────────────────────┤${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}1.${PLAIN} Create backup                      ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}2.${PLAIN} List backups                       ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}3.${PLAIN} Restore from backup                ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}0.${PLAIN} Back to main menu                  ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
    echo ""
    read -p "Please enter your choice [0-3]: " choice
    
    case "${choice}" in
        1)
            read -p "Enter backup name (optional): " name
            create_backup "${name}"
            ;;
        2)
            list_backups
            ;;
        3)
            list_backups
            read -p "Enter backup name to restore: " name
            restore_backup "${name}"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${PLAIN}"
            sleep 2
            show_backup_menu
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to the backup menu..." dummy
    show_backup_menu
}

# Backup and restore management
backup_config() {
    check_root
    init_backup
    
    if [[ $# -lt 2 ]]; then
        show_backup_menu
        return 0
    fi
    
    case "$2" in
        create)
            create_backup "$3"
            ;;
        list)
            list_backups
            ;;
        restore)
            restore_backup "$3"
            ;;
        *)
            echo -e "${RED}Unknown command: $2${PLAIN}"
            echo -e "${YELLOW}Usage: sbctl backup [create|list|restore]${PLAIN}"
            return 1
            ;;
    esac
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_config "$@"
fi
