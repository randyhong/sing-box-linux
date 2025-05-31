#!/bin/bash
#############################################
# Sing-box Installation Script
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
SUBSCRIPTION_DIR="${CONFIG_DIR}/subscriptions"
BACKUP_DIR="${CONFIG_DIR}/backups"
SERVICE_NAME="sing-box"
SCRIPT_PATH="/usr/bin/sbctl"

# Download URLs
GITHUB_URL="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz"
MIRROR_URLS=(
    "https://mirrors.huaweicloud.com/sing-box/sing-box-linux-amd64.tar.gz"
    "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz"
)

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

# Detect OS distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="${ID}"
        VERSION="${VERSION_ID}"
    else
        echo -e "${RED}Error: Cannot detect OS distribution!${PLAIN}"
        exit 1
    fi
    
    echo -e "${BLUE}Detected OS: ${OS} ${VERSION}${PLAIN}"
}

# Install dependencies
install_dependencies() {
    echo -e "${BLUE}Installing dependencies...${PLAIN}"
    
    case "${OS}" in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget tar jq ca-certificates systemd-resolved
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y curl wget tar jq ca-certificates
            ;;
        fedora)
            dnf install -y curl wget tar jq ca-certificates
            ;;
        alpine)
            apk add curl wget tar jq ca-certificates
            ;;
        *)
            echo -e "${RED}Unsupported OS: ${OS}${PLAIN}"
            exit 1
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Dependencies installed successfully!${PLAIN}"
    else
        echo -e "${RED}Failed to install dependencies!${PLAIN}"
        exit 1
    fi
}

# Download sing-box
download_sing_box() {
    echo -e "${BLUE}Downloading sing-box...${PLAIN}"
    
    TMP_DIR=$(mktemp -d)
    cd ${TMP_DIR}
    
    # Try GitHub URL first
    echo -e "${BLUE}Trying GitHub URL...${PLAIN}"
    if curl -sLo sing-box.tar.gz ${GITHUB_URL}; then
        echo -e "${GREEN}Download successful!${PLAIN}"
    else
        echo -e "${YELLOW}GitHub download failed, trying mirrors...${PLAIN}"
        
        # Try mirror URLs
        for mirror in "${MIRROR_URLS[@]}"; do
            echo -e "${BLUE}Trying mirror: ${mirror}${PLAIN}"
            if curl -sLo sing-box.tar.gz ${mirror}; then
                echo -e "${GREEN}Download successful!${PLAIN}"
                break
            else
                echo -e "${YELLOW}Mirror download failed, trying next...${PLAIN}"
            fi
        done
    fi
    
    # Check if download was successful
    if [[ ! -f sing-box.tar.gz ]]; then
        echo -e "${RED}All downloads failed!${PLAIN}"
        exit 1
    fi
    
    # Extract archive
    echo -e "${BLUE}Extracting archive...${PLAIN}"
    tar -xzf sing-box.tar.gz
    
    # Find the extracted directory
    EXTRACTED_DIR=$(find . -type d -name "sing-box*" | head -n 1)
    
    if [[ -z "${EXTRACTED_DIR}" ]]; then
        echo -e "${RED}Failed to extract archive!${PLAIN}"
        exit 1
    fi
    
    # Create installation directories
    echo -e "${BLUE}Creating installation directories...${PLAIN}"
    mkdir -p ${SING_BOX_DIR}
    mkdir -p ${CONFIG_DIR}
    mkdir -p ${LOG_DIR}
    mkdir -p ${SUBSCRIPTION_DIR}
    mkdir -p ${BACKUP_DIR}
    
    # Copy binary
    echo -e "${BLUE}Installing sing-box binary...${PLAIN}"
    cp ${EXTRACTED_DIR}/sing-box ${SING_BOX_DIR}/
    chmod +x ${SING_BOX_DIR}/sing-box
    
    # Clean up
    cd - > /dev/null
    rm -rf ${TMP_DIR}
    
    echo -e "${GREEN}Sing-box downloaded and installed successfully!${PLAIN}"
}

# Create default configuration
create_default_config() {
    echo -e "${BLUE}Creating default configuration...${PLAIN}"
    
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        cat > ${CONFIG_DIR}/config.json << 'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "geosite": "cn",
        "server": "local"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "mtu": 9000,
      "stack": "mixed",
      "endpoint_independent_nat": true
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["direct"]
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geoip": "private",
        "outbound": "direct"
      },
      {
        "geosite": "cn",
        "outbound": "direct"
      }
    ],
    "auto_detect_interface": true
  }
}
EOF
        echo -e "${GREEN}Default configuration created!${PLAIN}"
    else
        echo -e "${YELLOW}Configuration already exists, skipping...${PLAIN}"
    fi
}

# Create systemd service
create_systemd_service() {
    echo -e "${BLUE}Creating systemd service...${PLAIN}"
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=${SING_BOX_DIR}/sing-box run -C ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    # Create logrotate configuration
    cat > /etc/logrotate.d/sing-box << EOF
${LOG_DIR}/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload sing-box > /dev/null 2>&1 || true
    endscript
}
EOF
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    echo -e "${GREEN}Systemd service created!${PLAIN}"
}

# Create subscription update timer
create_subscription_timer() {
    echo -e "${BLUE}Creating subscription update timer...${PLAIN}"
    
    cat > /etc/systemd/system/sing-box-subscription.service << EOF
[Unit]
Description=Sing-box subscription update service
After=network.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} subscribe update
EOF
    
    cat > /etc/systemd/system/sing-box-subscription.timer << EOF
[Unit]
Description=Sing-box subscription update timer

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd daemon
    systemctl daemon-reload
    systemctl enable sing-box-subscription.timer
    
    echo -e "${GREEN}Subscription timer created!${PLAIN}"
}

# Install sbctl script
install_sbctl() {
    echo -e "${BLUE}Installing sbctl script...${PLAIN}"
    
    # Copy the script to /usr/bin
    cp $(dirname "$0")/sbctl ${SCRIPT_PATH}
    chmod +x ${SCRIPT_PATH}
    
    echo -e "${GREEN}Sbctl script installed!${PLAIN}"
}

# Start sing-box service
start_service() {
    echo -e "${BLUE}Starting sing-box service...${PLAIN}"
    
    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${GREEN}Sing-box service started successfully!${PLAIN}"
    else
        echo -e "${RED}Failed to start sing-box service!${PLAIN}"
        exit 1
    fi
}

# Uninstall sing-box
uninstall_sing_box() {
    echo -e "${BLUE}Uninstalling sing-box...${PLAIN}"
    
    # Stop and disable services
    systemctl stop ${SERVICE_NAME} 2>/dev/null
    systemctl disable ${SERVICE_NAME} 2>/dev/null
    systemctl stop sing-box-subscription.timer 2>/dev/null
    systemctl disable sing-box-subscription.timer 2>/dev/null
    
    # Remove files
    rm -rf ${SING_BOX_DIR}
    rm -f ${SCRIPT_PATH}
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f /etc/systemd/system/sing-box-subscription.service
    rm -f /etc/systemd/system/sing-box-subscription.timer
    rm -f /etc/logrotate.d/sing-box
    
    # Ask if user wants to remove configuration
    read -p "Do you want to remove configuration files? (y/n): " remove_config
    if [[ "${remove_config}" == "y" || "${remove_config}" == "Y" ]]; then
        rm -rf ${CONFIG_DIR}
        rm -rf ${LOG_DIR}
        echo -e "${GREEN}Configuration files removed!${PLAIN}"
    else
        echo -e "${YELLOW}Configuration files kept at ${CONFIG_DIR}${PLAIN}"
    fi
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    echo -e "${GREEN}Sing-box uninstalled successfully!${PLAIN}"
}

# Update sing-box
update_sing_box() {
    echo -e "${BLUE}Updating sing-box...${PLAIN}"
    
    # Stop service
    systemctl stop ${SERVICE_NAME}
    
    # Backup binary
    if [[ -f "${SING_BOX_DIR}/sing-box" ]]; then
        cp ${SING_BOX_DIR}/sing-box ${SING_BOX_DIR}/sing-box.bak
    fi
    
    # Download new version
    download_sing_box
    
    # Start service
    systemctl start ${SERVICE_NAME}
    
    echo -e "${GREEN}Sing-box updated successfully!${PLAIN}"
}

# Main function
main() {
    check_root
    check_systemd
    detect_os
    
    case "$1" in
        uninstall)
            uninstall_sing_box
            ;;
        update)
            install_dependencies
            update_sing_box
            ;;
        *)
            install_dependencies
            download_sing_box
            create_default_config
            create_systemd_service
            create_subscription_timer
            install_sbctl
            start_service
            
            echo -e "${GREEN}┌─────────────────────────────────────────┐${PLAIN}"
            echo -e "${GREEN}│      Sing-box installed successfully!   │${PLAIN}"
            echo -e "${GREEN}├─────────────────────────────────────────┤${PLAIN}"
            echo -e "${GREEN}│${PLAIN} Run ${BLUE}sbctl${PLAIN} to manage sing-box            ${GREEN}│${PLAIN}"
            echo -e "${GREEN}└─────────────────────────────────────────┘${PLAIN}"
            ;;
    esac
}

# Execute main function
main "$@"
