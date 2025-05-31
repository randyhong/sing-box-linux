#!/bin/bash
#############################################
# Sing-box Subscription Management
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
SUBSCRIPTION_DIR="${CONFIG_DIR}/subscriptions"
SUBSCRIPTION_LIST="${SUBSCRIPTION_DIR}/list.json"

# Check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

# Initialize subscription directory
init_subscription() {
    if [[ ! -d "${SUBSCRIPTION_DIR}" ]]; then
        mkdir -p "${SUBSCRIPTION_DIR}"
    fi
    
    if [[ ! -f "${SUBSCRIPTION_LIST}" ]]; then
        echo '{"subscriptions":[]}' > "${SUBSCRIPTION_LIST}"
    fi
}

# Add a subscription
add_subscription() {
    local url="$1"
    local name="$2"
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Error: URL is required!${PLAIN}"
        return 1
    fi
    
    if [[ -z "${name}" ]]; then
        name=$(echo "${url}" | md5sum | cut -d' ' -f1)
    fi
    
    # Check if subscription already exists
    local exists=$(jq -r ".subscriptions[] | select(.url == \"${url}\") | .url" "${SUBSCRIPTION_LIST}")
    if [[ -n "${exists}" ]]; then
        echo -e "${YELLOW}Subscription already exists!${PLAIN}"
        return 0
    fi
    
    # Add subscription to list
    jq --arg url "${url}" --arg name "${name}" '.subscriptions += [{"name": $name, "url": $url, "last_update": ""}]' "${SUBSCRIPTION_LIST}" > "${SUBSCRIPTION_LIST}.tmp"
    mv "${SUBSCRIPTION_LIST}.tmp" "${SUBSCRIPTION_LIST}"
    
    echo -e "${GREEN}Subscription added successfully!${PLAIN}"
    
    # Update subscription immediately
    update_subscription "${url}"
}

# Remove a subscription
remove_subscription() {
    local url="$1"
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Error: URL is required!${PLAIN}"
        return 1
    fi
    
    # Check if subscription exists
    local exists=$(jq -r ".subscriptions[] | select(.url == \"${url}\") | .url" "${SUBSCRIPTION_LIST}")
    if [[ -z "${exists}" ]]; then
        echo -e "${YELLOW}Subscription does not exist!${PLAIN}"
        return 0
    fi
    
    # Remove subscription from list
    jq --arg url "${url}" '.subscriptions = [.subscriptions[] | select(.url != $url)]' "${SUBSCRIPTION_LIST}" > "${SUBSCRIPTION_LIST}.tmp"
    mv "${SUBSCRIPTION_LIST}.tmp" "${SUBSCRIPTION_LIST}"
    
    # Remove subscription files
    local name=$(jq -r ".subscriptions[] | select(.url == \"${url}\") | .name" "${SUBSCRIPTION_LIST}")
    rm -f "${SUBSCRIPTION_DIR}/${name}.yaml"
    rm -f "${SUBSCRIPTION_DIR}/${name}.json"
    
    echo -e "${GREEN}Subscription removed successfully!${PLAIN}"
}

# List all subscriptions
list_subscriptions() {
    local count=$(jq -r '.subscriptions | length' "${SUBSCRIPTION_LIST}")
    
    if [[ "${count}" -eq 0 ]]; then
        echo -e "${YELLOW}No subscriptions found!${PLAIN}"
        return 0
    fi
    
    echo -e "${BLUE}Subscriptions:${PLAIN}"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│ ${PLAIN}Name                 │ URL                                    │ Last Update    ${BLUE}│${PLAIN}"
    echo -e "${BLUE}├─────────────────────────────────────────────────────────────────────────────┤${PLAIN}"
    
    jq -r '.subscriptions[] | "\(.name) \(.url) \(.last_update)"' "${SUBSCRIPTION_LIST}" | while read name url last_update; do
        printf "${BLUE}│${PLAIN} %-20s │ %-40s │ %-15s ${BLUE}│${PLAIN}\n" "${name}" "${url}" "${last_update}"
    done
    
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${PLAIN}"
}

# Convert Clash subscription to sing-box configuration
convert_clash_to_singbox() {
    local clash_file="$1"
    local output_file="$2"
    
    if [[ ! -f "${clash_file}" ]]; then
        echo -e "${RED}Error: Clash file not found!${PLAIN}"
        return 1
    fi
    
    echo -e "${BLUE}Converting Clash subscription to sing-box configuration...${PLAIN}"
    
    # Extract proxies from Clash configuration
    local proxies=$(yq -r '.proxies' "${clash_file}")
    
    # Create sing-box configuration template
    cat > "${output_file}" << 'EOF'
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
      "outbounds": ["auto"]
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": [],
      "interval": "5m",
      "tolerance": 100
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
    
    # Process each proxy and add to sing-box configuration
    local i=0
    local outbounds=""
    local auto_outbounds=""
    
    yq -r '.proxies[] | @json' "${clash_file}" | while read -r proxy; do
        local type=$(echo "${proxy}" | jq -r '.type')
        local name=$(echo "${proxy}" | jq -r '.name')
        local server=$(echo "${proxy}" | jq -r '.server')
        local port=$(echo "${proxy}" | jq -r '.port')
        
        case "${type}" in
            ss|shadowsocks)
                local method=$(echo "${proxy}" | jq -r '.cipher')
                local password=$(echo "${proxy}" | jq -r '.password')
                
                local outbound=$(cat << EOF
    {
      "type": "shadowsocks",
      "tag": "proxy_${i}",
      "server": "${server}",
      "server_port": ${port},
      "method": "${method}",
      "password": "${password}"
    }
EOF
                )
                ;;
            vmess)
                local uuid=$(echo "${proxy}" | jq -r '.uuid')
                local alter_id=$(echo "${proxy}" | jq -r '.alterId // 0')
                local security=$(echo "${proxy}" | jq -r '.cipher // "auto"')
                
                local outbound=$(cat << EOF
    {
      "type": "vmess",
      "tag": "proxy_${i}",
      "server": "${server}",
      "server_port": ${port},
      "uuid": "${uuid}",
      "security": "${security}",
      "alter_id": ${alter_id}
    }
EOF
                )
                ;;
            trojan)
                local password=$(echo "${proxy}" | jq -r '.password')
                
                local outbound=$(cat << EOF
    {
      "type": "trojan",
      "tag": "proxy_${i}",
      "server": "${server}",
      "server_port": ${port},
      "password": "${password}"
    }
EOF
                )
                ;;
            *)
                echo -e "${YELLOW}Unsupported proxy type: ${type}, skipping...${PLAIN}"
                continue
                ;;
        esac
        
        # Add outbound to list
        if [[ -z "${outbounds}" ]]; then
            outbounds="${outbound}"
        else
            outbounds="${outbounds},${outbound}"
        fi
        
        # Add to auto outbounds
        if [[ -z "${auto_outbounds}" ]]; then
            auto_outbounds="\"proxy_${i}\""
        else
            auto_outbounds="${auto_outbounds},\"proxy_${i}\""
        fi
        
        i=$((i+1))
    done
    
    # Update sing-box configuration with outbounds
    jq --argjson outbounds "[${outbounds}]" --argjson auto_outbounds "[${auto_outbounds}]" '.outbounds += $outbounds | .outbounds[1].outbounds = $auto_outbounds' "${output_file}" > "${output_file}.tmp"
    mv "${output_file}.tmp" "${output_file}"
    
    echo -e "${GREEN}Conversion completed!${PLAIN}"
}

# Update a subscription
update_subscription() {
    local url="$1"
    local subscriptions=()
    
    if [[ -z "${url}" ]]; then
        # Update all subscriptions
        subscriptions=($(jq -r '.subscriptions[].url' "${SUBSCRIPTION_LIST}"))
    else
        # Update specific subscription
        subscriptions=("${url}")
    fi
    
    for sub_url in "${subscriptions[@]}"; do
        echo -e "${BLUE}Updating subscription: ${sub_url}${PLAIN}"
        
        # Get subscription name
        local name=$(jq -r ".subscriptions[] | select(.url == \"${sub_url}\") | .name" "${SUBSCRIPTION_LIST}")
        
        # Download subscription
        local yaml_file="${SUBSCRIPTION_DIR}/${name}.yaml"
        local json_file="${SUBSCRIPTION_DIR}/${name}.json"
        
        if curl -s -o "${yaml_file}" "${sub_url}"; then
            echo -e "${GREEN}Download successful!${PLAIN}"
            
            # Convert to sing-box configuration
            convert_clash_to_singbox "${yaml_file}" "${json_file}"
            
            # Update last update time
            local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
            jq --arg url "${sub_url}" --arg time "${timestamp}" '.subscriptions = [.subscriptions[] | if .url == $url then .last_update = $time else . end]' "${SUBSCRIPTION_LIST}" > "${SUBSCRIPTION_LIST}.tmp"
            mv "${SUBSCRIPTION_LIST}.tmp" "${SUBSCRIPTION_LIST}"
            
            # Create backup
            local backup_dir="${SUBSCRIPTION_DIR}/backups/${name}"
            mkdir -p "${backup_dir}"
            cp "${json_file}" "${backup_dir}/$(date +%Y%m%d%H%M%S).json"
            
            # Keep only the last 5 backups
            ls -t "${backup_dir}"/*.json | tail -n +6 | xargs rm -f 2>/dev/null
            
            # Update main configuration
            echo -e "${BLUE}Updating main configuration...${PLAIN}"
            cp "${json_file}" "${CONFIG_DIR}/config.json"
            
            echo -e "${GREEN}Subscription updated successfully!${PLAIN}"
        else
            echo -e "${RED}Failed to download subscription!${PLAIN}"
        fi
    done
}

# Show subscription menu
show_subscription_menu() {
    clear
    echo -e "${BLUE}┌─────────────────────────────────────────┐${PLAIN}"
    echo -e "${BLUE}│       Subscription Management Menu      │${PLAIN}"
    echo -e "${BLUE}├─────────────────────────────────────────┤${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}1.${PLAIN} Add subscription                    ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}2.${PLAIN} Remove subscription                 ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}3.${PLAIN} List subscriptions                  ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}4.${PLAIN} Update all subscriptions            ${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} ${GREEN}0.${PLAIN} Back to main menu                  ${BLUE}│${PLAIN}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${PLAIN}"
    echo ""
    read -p "Please enter your choice [0-4]: " choice
    
    case "${choice}" in
        1)
            read -p "Enter subscription URL: " url
            read -p "Enter subscription name (optional): " name
            add_subscription "${url}" "${name}"
            ;;
        2)
            list_subscriptions
            read -p "Enter subscription URL to remove: " url
            remove_subscription "${url}"
            ;;
        3)
            list_subscriptions
            ;;
        4)
            update_subscription
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${PLAIN}"
            sleep 2
            show_subscription_menu
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to the subscription menu..." dummy
    show_subscription_menu
}

# Manage subscription
manage_subscription() {
    check_root
    init_subscription
    
    if [[ $# -lt 2 ]]; then
        show_subscription_menu
        return 0
    fi
    
    case "$2" in
        add)
            add_subscription "$3" "$4"
            ;;
        remove)
            remove_subscription "$3"
            ;;
        list)
            list_subscriptions
            ;;
        update)
            update_subscription "$3"
            ;;
        *)
            echo -e "${RED}Unknown command: $2${PLAIN}"
            echo -e "${YELLOW}Usage: sbctl subscribe [add|remove|list|update]${PLAIN}"
            return 1
            ;;
    esac
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    manage_subscription "$@"
fi
