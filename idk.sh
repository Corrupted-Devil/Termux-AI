#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           🌍 IP & Network Information Tool v2.0 🌍           ║
# ║          A comprehensive network diagnostics CLI            ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────
# 🎨 Color Definitions
# ──────────────────────────────────────────────
readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'

readonly BLACK='\033[0;30m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'

readonly BRED='\033[1;31m'
readonly BGREEN='\033[1;32m'
readonly BYELLOW='\033[1;33m'
readonly BBLUE='\033[1;34m'
readonly BMAGENTA='\033[1;35m'
readonly BCYAN='\033[1;36m'
readonly BWHITE='\033[1;37m'

readonly BG_BLACK='\033[40m'
readonly BG_RED='\033[41m'
readonly BG_GREEN='\033[42m'
readonly BG_YELLOW='\033[43m'
readonly BG_BLUE='\033[44m'
readonly BG_MAGENTA='\033[45m'
readonly BG_CYAN='\033[46m'
readonly BG_WHITE='\033[47m'

# ──────────────────────────────────────────────
# 📂 Global Variables
# ──────────────────────────────────────────────
readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly REPORT_FILE="network_report_$(date +%Y%m%d_%H%M%S).txt"
readonly TEMP_DIR="/tmp/netinfo_$$"
PUBLIC_IP=""
PUBLIC_IP_DATA=""
LOCAL_IP=""

mkdir -p "$TEMP_DIR"

# ──────────────────────────────────────────────
# 🛠️ Utility Functions
# ──────────────────────────────────────────────
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

print_separator() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

print_thin_separator() {
    echo -e "${DIM}──────────────────────────────────────────────────────────────────${RESET}"
}

print_header() {
    clear
    echo -e ""
    print_separator
    echo -e "${BCYAN}  ██████╗ ██████╗  █████╗ ███╗   ██╗████████╗ ██████╗ ███╗   ███╗${RESET}"
    echo -e "${BCYAN}  ██╔══██╗██╔══██╗██╔══██╗████╗  ██║╚══██╔══╝██╔═══██╗████╗ ████║${RESET}"
    echo -e "${BCYAN}  ██████╔╝██████╔╝███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║${RESET}"
    echo -e "${BCYAN}  ██╔═══╝ ██╔══██╗██╔══██║██║╚██╗██║   ██║   ██║   ██║██║╚██╔╝██║${RESET}"
    echo -e "${BCYAN}  ██║     ██║  ██║██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║${RESET}"
    echo -e "${BCYAN}  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝${RESET}"
    echo -e "${BYELLOW}                    🌍  Network Information Tool  🌍${RESET}"
    echo -e "${DIM}                              Version ${VERSION}${RESET}"
    print_separator
    echo -e ""
}

print_section() {
    local title="$1"
    echo -e ""
    echo -e "${BG_BLUE}${BWHITE}  📋 ${title} ${RESET}"
    print_thin_separator
}

print_kv() {
    local key="$1"
    local value="$2"
    local color="${3:-$WHITE}"
    local padding=28
    local padded_key
    padded_key=$(printf "%-${padding}s" "$key")
    echo -e "  ${BWHITE}${padded_key}${RESET} ${DIM}:${RESET} ${color}${value}${RESET}"
}

print_kv_colored() {
    local key="$1"
    local value="$2"
    local key_color="${3:-$BCYAN}"
    local val_color="${4:-$WHITE}"
    local padding=28
    local padded_key
    padded_key=$(printf "%-${padding}s" "$key")
    echo -e "  ${key_color}${padded_key}${RESET} ${DIM}:${RESET} ${val_color}${value}${RESET}"
}

success() {
    echo -e "  ${BGREEN}✔${RESET} ${GREEN}$1${RESET}"
}

error() {
    echo -e "  ${BRED}✖${RESET} ${RED}$1${RESET}"
}

warn() {
    echo -e "  ${BYELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

info() {
    echo -e "  ${BCYAN}ℹ${RESET} ${CYAN}$1${RESET}"
}

prompt() {
    local msg="$1"
    echo -ne "  ${BYELLOW}▶${RESET} ${YELLOW}${msg}${RESET} "
}

wait_for_key() {
    echo -e ""
    prompt "Press [Enter] to return to menu..."
    read -r
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        return 1
    fi
    return 0
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
            return 1
        fi
    fi
    return 0
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        warn "Some features may require root privileges."
        echo -e "  ${DIM}Consider running with: sudo $SCRIPT_NAME${RESET}"
        return 1
    fi
    return 0
}

spinner() {
    local pid=$1
    local message="${2:-Loading}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % ${#spin} ))
        printf "\r  ${BCYAN}%s${RESET} %s" "${spin:$i:1}" "$message..."
        sleep 0.1
    done
    printf "\r%$(tput cols)s\r"
}

# ──────────────────────────────────────────────
# 🌐 Feature 1: Public IP Address
# ──────────────────────────────────────────────
get_public_ip() {
    print_section "🌐 Public IP Address"

    if ! check_internet; then
        error "No internet connection detected!"
        wait_for_key
        return
    fi

    prompt "Fetching public IP..."
    echo -e ""

    PUBLIC_IP=$(curl -s --max-time 10 -f "https://api.ipify.org?format=json" 2>/dev/null | grep -oP '"ip":\s*"\K[^"]+' 2>/dev/null)

    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 10 -f "https://icanhazip.com" 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 10 -f "https://ifconfig.me" 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 10 -f "https://api64.ipify.org" 2>/dev/null | tr -d '[:space:]')
    fi

    if [[ -n "$PUBLIC_IP" ]]; then
        echo -e "  ┌──────────────────────────────────────────────┐"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  │${BGREEN}   🔗 Your Public IP: ${BWHITE}${BOLD}${PUBLIC_IP}${BGREEN}           ${RESET}│"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  └──────────────────────────────────────────────┘"

        # Detect IP version
        if echo "$PUBLIC_IP" | grep -q ':'; then
            info "IP Version: IPv6"
        else
            info "IP Version: IPv4"
        fi

        # IP class for IPv4
        if ! echo "$PUBLIC_IP" | grep -q ':'; then
            local first_octet
            first_octet=$(echo "$PUBLIC_IP" | cut -d'.' -f1)
            local ip_class=""
            case "$first_octet" in
                1-126)  ip_class="Class A" ;;
                128-191) ip_class="Class B" ;;
                192-223) ip_class="Class C" ;;
                224-239) ip_class="Class D (Multicast)" ;;
                240-255) ip_class="Class E (Reserved)" ;;
            esac
            info "IP Class: $ip_class"
        fi
    else
        error "Could not retrieve public IP address."
        error "Please check your internet connection."
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📍 Feature 2: IP Geolocation
# ──────────────────────────────────────────────
get_geolocation() {
    print_section "📍 IP Geolocation"

    if ! check_internet; then
        error "No internet connection detected!"
        wait_for_key
        return
    fi

    prompt "Fetching geolocation data..."
    echo -e ""

    local geo_data
    geo_data=$(curl -s --max-time 15 -f "https://ipapi.co/json/" 2>/dev/null)

    if [[ -z "$geo_data" ]] || echo "$geo_data" | grep -qi "error\|rate\|limit"; then
        # Fallback to ipinfo.io
        geo_data=$(curl -s --max-time 15 -f "https://ipinfo.io/json" 2>/dev/null)
    fi

    if [[ -z "$geo_data" ]]; then
        error "Could not fetch geolocation data."
        wait_for_key
        return
    fi

    # Parse ipapi.co format
    if echo "$geo_data" | grep -q '"city"'; then
        local ip city region country country_name timezone isp org asn latitude longitude postal
        ip=$(echo "$geo_data" | grep -oP '"ip":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        city=$(echo "$geo_data" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        region=$(echo "$geo_data" | grep -oP '"region":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        country=$(echo "$geo_data" | grep -oP '"country_code":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        country_name=$(echo "$geo_data" | grep -oP '"country_name":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        timezone=$(echo "$geo_data" | grep -oP '"timezone":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        isp=$(echo "$geo_data" | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        latitude=$(echo "$geo_data" | grep -oP '"latitude":\s*\K[^,]+' 2>/dev/null || echo "N/A")
        longitude=$(echo "$geo_data" | grep -oP '"longitude":\s*\K[^,]+' 2>/dev/null || echo "N/A")
        postal=$(echo "$geo_data" | grep -oP '"postal":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        asn=$(echo "$geo_data" | grep -oP '"asn":\s*"\K[^"]+' 2>/dev/null || echo "N/A")

        print_kv "IP Address" "$ip" "$BGREEN"
        print_kv "City" "$city" "$BCYAN"
        print_kv "Region/State" "$region" "$BCYAN"
        print_kv "Country" "${country_name} (${country})" "$BCYAN"
        print_kv "Postal Code" "$postal" "$BCYAN"
        print_kv "Coordinates" "${latitude}, ${longitude}" "$BMAGENTA"
        print_kv "Timezone" "$timezone" "$BYELLOW"
        print_kv "ISP / Org" "$isp" "$BWHITE"
        print_kv "ASN" "$asn" "$BWHITE"

        PUBLIC_IP="$ip"
        PUBLIC_IP_DATA="$geo_data"

    # Parse ipinfo.io format
    elif echo "$geo_data" | grep -q '"loc"'; then
        local ip city region country org timezone loc postal hostname
        ip=$(echo "$geo_data" | grep -oP '"ip":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        city=$(echo "$geo_data" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        region=$(echo "$geo_data" | grep -oP '"region":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        country=$(echo "$geo_data" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        org=$(echo "$geo_data" | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        timezone=$(echo "$geo_data" | grep -oP '"timezone":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        loc=$(echo "$geo_data" | grep -oP '"loc":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        postal=$(echo "$geo_data" | grep -oP '"postal":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        hostname=$(echo "$geo_data" | grep -oP '"hostname":\s*"\K[^"]+' 2>/dev/null || echo "N/A")

        print_kv "IP Address" "$ip" "$BGREEN"
        print_kv "Hostname" "$hostname" "$BCYAN"
        print_kv "City" "$city" "$BCYAN"
        print_kv "Region/State" "$region" "$BCYAN"
        print_kv "Country" "$country" "$BCYAN"
        print_kv "Postal Code" "$postal" "$BCYAN"
        print_kv "Coordinates" "$loc" "$BMAGENTA"
        print_kv "Timezone" "$timezone" "$BYELLOW"
        print_kv "Organization" "$org" "$BWHITE"

        PUBLIC_IP="$ip"
        PUBLIC_IP_DATA="$geo_data"
    else
        error "Unable to parse geolocation data."
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🏠 Feature 3: Local IP Address
# ──────────────────────────────────────────────
get_local_ip() {
    print_section "🏠 Local IP Address"

    local interfaces
    local found=0

    if check_command "ip"; then
        interfaces=$(ip -4 addr show 2>/dev/null | grep -oP '^\d+:\s+\K[^:]+' | grep -v '^lo$')
    elif check_command "ifconfig"; then
        interfaces=$(ifconfig 2>/dev/null | grep -oP '^\K[a-zA-Z0-9]+' | grep -v '^lo$')
    else
        error "Neither 'ip' nor 'ifconfig' command found."
        wait_for_key
        return
    fi

    for iface in $interfaces; do
        local ip_addr
        local mac_addr=""

        if check_command "ip"; then
            ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet\s+\K[^/]+' | head -1)
            mac_addr=$(ip link show "$iface" 2>/dev/null | grep -oP 'link/ether\s+\K[^ ]+' | head -1)
        elif check_command "ifconfig"; then
            ip_addr=$(ifconfig "$iface" 2>/dev/null | grep -oP 'inet\s+\K[^ ]+' | head -1)
            mac_addr=$(ifconfig "$iface" 2>/dev/null | grep -oP 'ether\s+\K[^ ]+' | head -1)
        fi

        if [[ -n "$ip_addr" ]]; then
            if [[ $found -eq 0 ]]; then
                echo -e "  ┌──────────────────────────────────────────────┐"
                echo -e "  │${BGREEN}   🔗 Primary Local IP: ${BWHITE}${BOLD}${ip_addr}${BGREEN}          ${RESET}│"
                echo -e "  └──────────────────────────────────────────────┘"
                LOCAL_IP="$ip_addr"
                found=1
            fi
            echo -e ""
            print_kv_colored "Interface" "$iface" "$BCYAN" "$BWHITE"
            print_kv_colored "IPv4 Address" "$ip_addr" "$BCYAN" "$BGREEN"
            if [[ -n "$mac_addr" ]]; then
                print_kv_colored "MAC Address" "$mac_addr" "$BCYAN" "$BMAGENTA"
            fi

            # Get interface status
            local operstate=""
            if [[ -f "/sys/class/net/${iface}/operstate" ]]; then
                operstate=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null)
            fi
            if [[ "$operstate" == "up" ]]; then
                print_kv_colored "Status" "UP ●" "$BCYAN" "$BGREEN"
            else
                print_kv_colored "Status" "DOWN ○" "$BCYAN" "$BRED"
            fi
            print_thin_separator
        fi
    done

    if [[ $found -eq 0 ]]; then
        warn "No active local IP addresses found."
    fi

    # Also show IPv6 local addresses
    echo -e ""
    info "IPv6 Local Addresses:"
    if check_command "ip"; then
        ip -6 addr show 2>/dev/null | grep -oP 'inet6\s+\K[^/]+' | grep -v '^::1$' | grep -v '^fe80' | while read -r ipv6; do
            if [[ -n "$ipv6" ]]; then
                echo -e "    ${BMAGENTA}➜${RESET} ${GREEN}${ipv6}${RESET}"
            fi
        done
        # Show link-local
        echo -e ""
        info "Link-Local IPv6:"
        ip -6 addr show 2>/dev/null | grep -oP 'inet6\s+\K[^/]+' | grep '^fe80' | while read -r ipv6; do
            if [[ -n "$ipv6" ]]; then
                echo -e "    ${BMAGENTA}➜${RESET} ${DIM}${ipv6}${RESET}"
            fi
        done
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🖥️ Feature 4: Hostname
# ──────────────────────────────────────────────
show_hostname() {
    print_section "🖥️  Hostname Information"

    local hostname_val fqdn_val domain_val

    hostname_val=$(hostname 2>/dev/null || echo "N/A")
    fqdn_val=$(hostname -f 2>/dev/null || hostname --fqdn 2>/dev/null || echo "N/A")
    domain_val=$(hostname -d 2>/dev/null || hostname --domain 2>/dev/null || echo "N/A")

    print_kv "Hostname" "$hostname_val" "$BGREEN"
    print_kv "FQDN" "$fqdn_val" "$BCYAN"
    print_kv "Domain" "$domain_val" "$BYELLOW"

    # OS info
    echo -e ""
    info "System Information:"
    print_kv "OS" "$(uname -s)" "$BWHITE"
    print_kv "Kernel" "$(uname -r)" "$BWHITE"
    print_kv "Architecture" "$(uname -m)" "$BWHITE"
    print_kv "User" "$(whoami)" "$BCYAN"

    if [[ -f /etc/os-release ]]; then
        local os_name os_version
        os_name=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "N/A")
        print_kv "Distribution" "$os_name" "$BMAGENTA"
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📡 Feature 5: Network Interface Details
# ──────────────────────────────────────────────
show_interfaces() {
    print_section "📡 Network Interface Details"

    if check_command "ip"; then
        echo -e ""
        ip -brief addr show 2>/dev/null | while IFS= read -r line; do
            local iface status ip_info
            iface=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            ip_info=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^ *//')

            if [[ "$status" == "UP" || "$status" == "UNKNOWN" ]]; then
                printf "  ${BGREEN}●${RESET} %-16s ${GREEN}%-8s${RESET} %s\n" "$iface" "$status" "$ip_info"
            else
                printf "  ${BRED}○${RESET} %-16s ${RED}%-8s${RESET} %s\n" "$iface" "$status" "$ip_info"
            fi
        done

        echo -e ""
        print_thin_separator
        echo -e ""
        info "Detailed Interface Statistics:"
        echo -e ""

        ip -stats link show 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^[0-9]+: ]]; then
                echo -e "  ${BCYAN}${line}${RESET}"
            elif [[ "$line" =~ [[:space:]]+(RX|TX) ]]; then
                echo -e "  ${DIM}${line}${RESET}"
            elif [[ -n "$line" ]]; then
                echo -e "  ${WHITE}${line}${RESET}"
            fi
        done

    elif check_command "ifconfig"; then
        ifconfig -a 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                echo -e "  ${BCYAN}${line}${RESET}"
            else
                echo -e "  ${WHITE}${line}${RESET}"
            fi
        done
    else
        error "Neither 'ip' nor 'ifconfig' command found."
    fi

    # Wireless info
    if check_command "iwconfig"; then
        echo -e ""
        info "Wireless Interfaces:"
        iwconfig 2>/dev/null | grep -v "no wireless" | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                echo -e "  ${BMAGENTA}${line}${RESET}"
            fi
        done
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🚪 Feature 6: Default Gateway
# ──────────────────────────────────────────────
show_gateway() {
    print_section "🚪 Default Gateway"

    local gateway_iface=""

    if check_command "ip"; then
        gateway_iface=$(ip route show default 2>/dev/null)
    elif check_command "netstat"; then
        gateway_iface=$(netstat -rn 2>/dev/null | grep "^0.0.0.0" | head -1)
    elif check_command "route"; then
        gateway_iface=$(route -n 2>/dev/null | grep "^0.0.0.0" | head -1)
    fi

    if [[ -n "$gateway_iface" ]]; then
        if check_command "ip"; then
            local gw_ip gw_via gw_dev
            gw_ip=$(echo "$gateway_iface" | grep -oP 'via\s+\K[^ ]+' || echo "")
            gw_dev=$(echo "$gateway_iface" | grep -oP 'dev\s+\K[^ ]+' || echo "")
            gw_via=$(echo "$gateway_iface" | grep -oP 'src\s+\K[^ ]+' || echo "")

            echo -e "  ┌──────────────────────────────────────────────┐"
            echo -e "  │${BYELLOW}   🚪 Gateway IP: ${BWHITE}${BOLD}${gw_ip:-N/A}${BYELLOW}               ${RESET}│"
            echo -e "  └──────────────────────────────────────────────┘"
            echo -e ""
            print_kv "Gateway IP" "${gw_ip:-N/A}" "$BGREEN"
            print_kv "Interface" "${gw_dev:-N/A}" "$BCYAN"
            print_kv "Source IP" "${gw_via:-N/A}" "$BYELLOW"
        else
            echo -e "  ${WHITE}${gateway_iface}${RESET}"
        fi

        # Show full routing table
        echo -e ""
        info "Routing Table:"
        echo -e ""
        if check_command "ip"; then
            ip route show 2>/dev/null | head -20 | while IFS= read -r route; do
                echo -e "  ${DIM}➜${RESET} ${WHITE}${route}${RESET}"
            done
            local total_routes
            total_routes=$(ip route show 2>/dev/null | wc -l)
            if [[ "$total_routes" -gt 20 ]]; then
                echo -e "  ${DIM}... and $((total_routes - 20)) more routes${RESET}"
            fi
        fi
    else
        warn "No default gateway found."
    fi

    # IPv6 default route
    if check_command "ip"; then
        local v6_gw
        v6_gw=$(ip -6 route show default 2>/dev/null)
        if [[ -n "$v6_gw" ]]; then
            echo -e ""
            info "IPv6 Default Gateway:"
            echo -e "  ${BMAGENTA}${v6_gw}${RESET}"
        fi
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🌍 Feature 7: DNS Servers
# ──────────────────────────────────────────────
show_dns() {
    print_section "🌍 DNS Servers"

    local dns_found=0

    # Method 1: resolvectl
    if check_command "resolvectl"; then
        echo -e ""
        info "DNS from resolvectl:"
        resolvectl status 2>/dev/null | grep "DNS Servers" | while IFS= read -r line; do
            local servers
            servers=$(echo "$line" | sed 's/.*DNS Servers: //')
            for srv in $servers; do
                printf "  ${BGREEN}◆${RESET} %s\n" "$srv"
                dns_found=1
            done
        done
    fi

    # Method 2: /etc/resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        echo -e ""
        info "DNS from /etc/resolv.conf:"
        grep -E '^\s*nameserver' /etc/resolv.conf 2>/dev/null | while IFS= read -r line; do
            local ns
            ns=$(echo "$line" | awk '{print $2}')
            printf "  ${BGREEN}◆${RESET} %s\n" "$ns"
            dns_found=1
        done
    fi

    # Method 3: nmcli
    if check_command "nmcli"; then
        echo -e ""
        info "DNS from NetworkManager:"
        nmcli dev show 2>/dev/null | grep -E "IP4.DNS|IP6.DNS" | while IFS= read -r line; do
            local dns_val
            dns_val=$(echo "$line" | awk -F: '{print $2}' | sed 's/^[[:space:]]*//')
            printf "  ${BGREEN}◆${RESET} %s\n" "$dns_val"
            dns_found=1
        done
    fi

    if [[ $dns_found -eq 0 ]]; then
        warn "No DNS servers found."
    fi

    # Test DNS resolution
    echo -e ""
    info "DNS Resolution Test:"
    local dns_test_domains=("google.com" "cloudflare.com" "github.com")
    for domain in "${dns_test_domains[@]}"; do
        local resolved_ip=""
        if check_command "dig"; then
            resolved_ip=$(dig +short "$domain" A +timeout=3 2>/dev/null | head -1)
        elif check_command "nslookup"; then
            resolved_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
        elif check_command "host"; then
            resolved_ip=$(host -W 3 "$domain" 2>/dev/null | grep "has address" | awk '{print $4}' | head -1)
        fi

        if [[ -n "$resolved_ip" ]]; then
            printf "  ${BGREEN}✔${RESET} %-20s → ${GREEN}%s${RESET}\n" "$domain" "$resolved_ip"
        else
            printf "  ${BRED}✖${RESET} %-20s → ${RED}FAILED${RESET}\n" "$domain"
        fi
    done

    wait_for_key
}

# ──────────────────────────────────────────────
# 📶 Feature 8: Ping Host
# ──────────────────────────────────────────────
ping_host() {
    print_section "📶 Ping Host"

    prompt "Enter host to ping [default: google.com]: "
    local target
    read -r target
    target="${target:-google.com}"

    echo -e ""
    info "Pinging ${BYELLOW}${target}${CYAN} (Ctrl+C to stop)..."
    echo -e ""
    print_thin_separator

    local ping_cmd="ping"
    local ping_opts="-c 4 -W 5"

    # Check if we should use ping6
    if echo "$target" | grep -q ':'; then
        if check_command "ping6"; then
            ping_cmd="ping6"
        else
            ping_opts="$ping_opts -6"
        fi
    fi

    if ! $ping_cmd $ping_opts "$target" 2>&1; then
        echo -e ""
        error "Ping failed for $target"
    fi

    print_thin_separator
    wait_for_key
}

# ──────────────────────────────────────────────
# 🔍 Feature 9: DNS Lookup
# ──────────────────────────────────────────────
dns_lookup() {
    print_section "🔍 DNS Lookup"

    prompt "Enter domain to look up [default: google.com]: "
    local domain
    read -r domain
    domain="${domain:-google.com}"

    echo -e ""

    # dig
    if check_command "dig"; then
        echo -e "  ${BCYAN}━━━ A Records ─━━${RESET}"
        dig +short "$domain" A +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BGREEN}◆${RESET} ${GREEN}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ AAAA Records (IPv6) ─━━${RESET}"
        dig +short "$domain" AAAA +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BMAGENTA}◆${RESET} ${MAGENTA}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ MX Records ─━━${RESET}"
        dig +short "$domain" MX +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BYELLOW}◆${RESET} ${YELLOW}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ NS Records ─━━${RESET}"
        dig +short "$domain" NS +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BCYAN}◆${RESET} ${CYAN}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ TXT Records ─━━${RESET}"
        dig +short "$domain" TXT +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BWHITE}◆${RESET} ${WHITE}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ CNAME Records ─━━${RESET}"
        dig +short "$domain" CNAME +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${BMAGENTA}◆${RESET} ${MAGENTA}${record}${RESET}"
        done

        echo -e ""
        echo -e "  ${BCYAN}━━━ SOA Record ─━━${RESET}"
        dig +short "$domain" SOA +timeout=5 2>/dev/null | while IFS= read -r record; do
            [[ -n "$record" ]] && echo -e "  ${DIM}◆${RESET} ${DIM}${record}${RESET}"
        done

    elif check_command "nslookup"; then
        echo -e "  ${BCYAN}━━━ DNS Lookup Results ─━━${RESET}"
        nslookup "$domain" 2>&1 | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done

    elif check_command "host"; then
        echo -e "  ${BCYAN}━━━ DNS Lookup Results ─━━${RESET}"
        host "$domain" 2>&1 | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done
    else
        error "No DNS lookup tool found (dig, nslookup, or host)."
    fi

    # Reverse DNS if target looks like IP
    if echo "$domain" | grep -qP '^\d{1,3}(\.\d{1,3}){3}$'; then
        echo -e ""
        echo -e "  ${BCYAN}━━━ Reverse DNS (PTR) ─━━${RESET}"
        if check_command "dig"; then
            local ptr
            ptr=$(dig +short -x "$domain" +timeout=5 2>/dev/null)
            if [[ -n "$ptr" ]]; then
                echo -e "  ${BGREEN}◆${RESET} ${GREEN}${ptr}${RESET}"
            else
                echo -e "  ${DIM}  No PTR record found${RESET}"
            fi
        fi
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🌐 Feature 10: Traceroute
# ──────────────────────────────────────────────
traceroute_host() {
    print_section "🌐 Traceroute"

    local tr_cmd=""
    if check_command "traceroute"; then
        tr_cmd="traceroute"
    elif check_command "tracepath"; then
        tr_cmd="tracepath"
    else
        error "Neither 'traceroute' nor 'tracepath' found."
        error "Install with: sudo apt install traceroute"
        wait_for_key
        return
    fi

    prompt "Enter host to trace [default: google.com]: "
    local target
    read -r target
    target="${target:-google.com}"

    echo -e ""
    info "Tracing route to ${BYELLOW}${target}${CYAN} (max 30 hops)..."
    echo -e ""
    print_thin_separator

    local tr_opts=""
    if [[ "$tr_cmd" == "traceroute" ]]; then
        tr_opts="-m 30 -w 2"
        # Try ICMP if available
        if $tr_cmd --help 2>&1 | grep -q "\-I"; then
            tr_opts="$tr_opts -I"
        fi
    fi

    if ! $tr_cmd $tr_opts "$target" 2>&1; then
        echo -e ""
        error "Traceroute failed for $target"
    fi

    print_thin_separator
    wait_for_key
}

# ──────────────────────────────────────────────
# 🚪 Feature 11: Check Open Ports
# ──────────────────────────────────────────────
check_ports() {
    print_section "🚪 Open Ports"

    local port_tool=""

    if check_command "ss"; then
        port_tool="ss"
    elif check_command "netstat"; then
        port_tool="netstat"
    else
        error "Neither 'ss' nor 'netstat' found."
        wait_for_key
        return
    fi

    echo -e ""

    # Listening TCP ports
    echo -e "  ${BGREEN}━━━ Listening TCP Ports ─━━${RESET}"
    echo -e ""
    if [[ "$port_tool" == "ss" ]]; then
        ss -tlnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
            local state local_addr remote_addr process
            state=$(echo "$line" | awk '{print $1}')
            local_addr=$(echo "$line" | awk '{print $4}')
            remote_addr=$(echo "$line" | awk '{print $5}')
            process=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; print $0}' | sed 's/^ *//')

            # Extract port
            local port
            port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)

            printf "  ${BGREEN}◆${RESET} ${GREEN}%-6s${RESET} ${CYAN}%-25s${RESET} ${DIM}%-25s${RESET} ${YELLOW}%s${RESET}\n" \
                "$state" "$local_addr" "$remote_addr" "$process"
        done
    else
        netstat -tlnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done
    fi

    echo -e ""
    echo -e "  ${BMAGENTA}━━━ Listening UDP Ports ─━━${RESET}"
    echo -e ""
    if [[ "$port_tool" == "ss" ]]; then
        ss -ulnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
            local state local_addr remote_addr process
            state=$(echo "$line" | awk '{print $1}')
            local_addr=$(echo "$line" | awk '{print $4}')
            remote_addr=$(echo "$line" | awk '{print $5}')
            process=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; print $0}' | sed 's/^ *//')

            printf "  ${BMAGENTA}◆${RESET} ${MAGENTA}%-6s${RESET} ${CYAN}%-25s${RESET} ${DIM}%-25s${RESET} ${YELLOW}%s${RESET}\n" \
                "$state" "$local_addr" "$remote_addr" "$process"
        done
    else
        netstat -ulnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done
    fi

    # Port count summary
    echo -e ""
    info "Summary:"
    if [[ "$port_tool" == "ss" ]]; then
        local tcp_count udp_count
        tcp_count=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l)
        udp_count=$(ss -ulnp 2>/dev/null | tail -n +2 | wc -l)
        print_kv "TCP Listening" "$tcp_count ports" "$BGREEN"
        print_kv "UDP Listening" "$udp_count ports" "$BMAGENTA"
    fi

    # Scan specific port on remote host
    echo -e ""
    prompt "Scan a specific port on a remote host? [y/N]: "
    local answer
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        prompt "Enter host: "
        local remote_host
        read -r remote_host

        prompt "Enter port [default: 80]: "
        local remote_port
        read -r remote_port
        remote_port="${remote_port:-80}"

        echo -e ""
        info "Checking ${BYELLOW}${remote_host}:${remote_port}${CYAN}..."
        echo -e ""

        if check_command "nc"; then
            if (echo >/dev/tcp/"$remote_host"/"$remote_port") &>/dev/null; then
                success "Port ${remote_port} is ${BGREEN}OPEN${RESET} on ${remote_host}"
            else
                error "Port ${remote_port} is ${BRED}CLOSED/FILTERED${RESET} on ${remote_host}"
            fi
        elif check_command "timeout" && check_command "bash"; then
            if timeout 5 bash -c "echo >/dev/tcp/$remote_host/$remote_port" 2>/dev/null; then
                success "Port ${remote_port} is ${BGREEN}OPEN${RESET} on ${remote_host}"
            else
                error "Port ${remote_port} is ${BRED}CLOSED/FILTERED${RESET} on ${remote_host}"
            fi
        else
            error "Cannot test port: 'nc' or bash /dev/tcp not available"
        fi
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# ⚡ Feature 12: Internet Speed Test
# ──────────────────────────────────────────────
speed_test() {
    print_section "⚡ Internet Speed Test"

    if ! check_internet; then
        error "No internet connection detected!"
        wait_for_key
        return
    fi

    echo -e "  ${DIM}Note: This uses curl-based download estimation, not a full speedtest.${RESET}"
    echo -e "  ${DIM}For accurate results, install speedtest-cli: pip3 install speedtest-cli${RESET}"
    echo -e ""

    # Check for speedtest-cli
    if check_command "speedtest-cli" || check_command "speedtest"; then
        prompt "speedtest-cli detected! Use it? [Y/n]: "
        local use_cli
        read -r use_cli
        if [[ ! "$use_cli" =~ ^[Nn]$ ]]; then
            echo -e ""
            if check_command "speedtest-cli"; then
                speedtest-cli --simple 2>&1 | while IFS= read -r line; do
                    echo -e "  ${BGREEN}⚡${RESET} ${BWHITE}${line}${RESET}"
                done
            else
                speedtest --simple 2>&1 | while IFS= read -r line; do
                    echo -e "  ${BGREEN}⚡${RESET} ${BWHITE}${line}${RESET}"
                done
            fi
            wait_for_key
            return
        fi
    fi

    # Curl-based download test
    local test_urls=(
        "https://speed.cloudflare.com/__down?bytes=10000000"
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
        "http://cachefly.cachefly.net/10mb.test"
    )
    local test_size_mb="10"
    local best_time=""
    local best_url=""

    info "Testing download speed with ${test_size_mb}MB file..."
    echo -e ""

    for url in "${test_urls[@]}"; do
        local download_time
        echo -ne "  ${BCYAN}⏳${RESET} Testing: ${DIM}${url:0:60}...${RESET} "
        download_time=$(curl -s -o /dev/null -w '%{time_total}' --max-time 30 "$url" 2>/dev/null || echo "999")

        if (( $(echo "$download_time < 999" | bc -l 2>/dev/null || echo 0) )); then
            local speed_mbps
            speed_mbps=$(echo "scale=2; ($test_size_mb * 8) / $download_time" | bc 2>/dev/null || echo "0")
            echo -e "${GREEN}${speed_mbps} Mbps${RESET}"

            if [[ -z "$best_time" ]] || (( $(echo "$download_time < $best_time" | bc -l 2>/dev/null || echo 0) )); then
                best_time="$download_time"
                best_url="$url"
            fi
        else
            echo -e "${RED}FAILED${RESET}"
        fi
    done

    if [[ -n "$best_time" ]] && (( $(echo "$best_time < 999" | bc -l 2>/dev/null || echo 0) )); then
        local speed_mbps
        speed_mbps=$(echo "scale=2; ($test_size_mb * 8) / $best_time" | bc 2>/dev/null || echo "0")
        local speed_mbytes
        speed_mbytes=$(echo "scale=2; $test_size_mb / $best_time" | bc 2>/dev/null || echo "0")

        echo -e ""
        echo -e "  ┌──────────────────────────────────────────────┐"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  │${BGREEN}   ⚡ Download Speed: ${BWHITE}${BOLD}${speed_mbps} Mbps${BGREEN}           ${RESET}│"
        echo -e "  │${BGREEN}   📥 ${speed_mbytes} MB/s${BGREEN}                          ${RESET}│"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  └──────────────────────────────────────────────┘"
    else
        error "Could not complete speed test."
    fi

    # Latency test
    echo -e ""
    info "Latency Test:"
    local ping_targets=("google.com" "cloudflare.com" "github.com")
    for target in "${ping_targets[@]}"; do
        local latency
        latency=$(ping -c 3 -W 3 "$target" 2>/dev/null | grep -oP 'rtt min/avg/max/mdev = \K[0-9.]+' | cut -d'/' -f2)
        if [[ -n "$latency" ]]; then
            printf "  ${BGREEN}◆${RESET} %-20s ${GREEN}%s ms${RESET}\n" "$target" "$latency"
        else
            printf "  ${BRED}✖${RESET} %-20s ${RED}timeout${RESET}\n" "$target"
        fi
    done

    wait_for_key
}

# ──────────────────────────────────────────────
# 🔒 Feature 13: VPN/Proxy Detection
# ──────────────────────────────────────────────
vpn_proxy_detect() {
    print_section "🔒 VPN/Proxy Detection"

    if ! check_internet; then
        error "No internet connection detected!"
        wait_for_key
        return
    fi

    prompt "Fetching VPN/Proxy status..."
    echo -e ""

    # Method 1: ip-api.com (free, no key needed)
    local vpn_data
    vpn_data=$(curl -s --max-time 15 "http://ip-api.com/json/?fields=query,country,city,isp,org,proxy,hosting,as" 2>/dev/null)

    if [[ -n "$vpn_data" ]] && ! echo "$vpn_data" | grep -qi "error\|rate"; then
        local ip country city isp org proxy hosting asn
        ip=$(echo "$vpn_data" | grep -oP '"query":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        country=$(echo "$vpn_data" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        city=$(echo "$vpn_data" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        isp=$(echo "$vpn_data" | grep -oP '"isp":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        org=$(echo "$vpn_data" | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        proxy=$(echo "$vpn_data" | grep -oP '"proxy":\s*\K[^,}]+' 2>/dev/null || echo "false")
        hosting=$(echo "$vpn_data" | grep -oP '"hosting":\s*\K[^,}]+' 2>/dev/null || echo "false")
        asn=$(echo "$vpn_data" | grep -oP '"as":\s*"\K[^"]+' 2>/dev/null || echo "N/A")

        print_kv "IP Address" "$ip" "$BGREEN"
        print_kv "Location" "${city}, ${country}" "$BCYAN"
        print_kv "ISP" "$isp" "$BWHITE"
        print_kv "Organization" "$org" "$BWHITE"
        print_kv "ASN" "$asn" "$BWHITE"

        echo -e ""
        echo -e "  ${BCYAN}━━━ Detection Results ─━━${RESET}"

        # Proxy detection
        if [[ "$proxy" == "true" ]]; then
            echo -e "  ${BRED}🔒 Proxy Detected: ${BWHITE}YES${RESET}"
            echo -e "  ${RED}   Your IP appears to be a proxy server.${RESET}"
        else
            echo -e "  ${BGREEN}🔓 Proxy Detected: ${BWHITE}NO${RESET}"
            echo -e "  ${GREEN}   Your IP does not appear to be a proxy.${RESET}"
        fi

        echo -e ""

        # Hosting detection
        if [[ "$hosting" == "true" ]]; then
            echo -e "  ${BYELLOW}🏢 Hosting/Data Center: ${BWHITE}YES${RESET}"
            echo -e "  ${YELLOW}   Your IP belongs to a hosting provider.${RESET}"
            echo -e "  ${YELLOW}   This is common with VPNs and proxies.${RESET}"
        else
            echo -e "  ${BGREEN}🏠 Residential IP: ${BWHITE}YES${RESET}"
            echo -e "  ${GREEN}   Your IP appears to be a residential connection.${RESET}"
        fi

        echo -e ""

        # Known VPN providers
        local known_vpn=false
        local vpn_patterns=("NordVPN" "ExpressVPN" "Surfshark" "CyberGhost" "ProtonVPN" \
                                       "Mullvad" "PIA" "Private Internet" "IPVanish" "Hide.me" \
                           "Windscribe" "TunnelBear" "Hotspot Shield" \
                           "DigitalOcean" "Linode" "Vultr" "AWS" "Amazon" \
                           "Google Cloud" "Microsoft Azure" "OVH" "Hetzner" \
                           "Cloudflare" "Oracle Cloud" "Alibaba Cloud")

        for vpn_name in "${vpn_patterns[@]}"; do
            if echo "$isp $org $asn" | grep -qi "$vpn_name"; then
                echo -e "  ${BMAGENTA}🛡️  Known VPN/Hosting Provider: ${BWHITE}${vpn_name}${RESET}"
                known_vpn=true
                break
            fi
        done

        if [[ "$known_vpn" == "false" ]]; then
            if [[ "$hosting" == "true" ]]; then
                echo -e "  ${BYELLOW}⚠️  Hosting provider detected but not in known VPN list.${RESET}"
            else
                echo -e "  ${BGREEN}✅ No known VPN/Proxy signatures detected.${RESET}"
            fi
        fi

    else
        # Fallback method: check via whois
        warn "ip-api.com unavailable. Using fallback method..."

        if [[ -z "$PUBLIC_IP" ]]; then
            PUBLIC_IP=$(curl -s --max-time 10 "https://api.ipify.org" 2>/dev/null)
        fi

        if [[ -n "$PUBLIC_IP" ]]; then
            print_kv "IP Address" "$PUBLIC_IP" "$BGREEN"

            if check_command "whois"; then
                echo -e ""
                info "WHOIS Analysis:"
                local org_name
                org_name=$(whois "$PUBLIC_IP" 2>/dev/null | grep -iE "^orgname|^organization|^owner" | head -3)
                if [[ -n "$org_name" ]]; then
                    echo -e "  ${WHITE}${org_name}${RESET}"
                fi

                local net_range
                net_range=$(whois "$PUBLIC_IP" 2>/dev/null | grep -iE "^netrange|^inetnum|^cidr" | head -1)
                if [[ -n "$net_range" ]]; then
                    echo -e "  ${DIM}${net_range}${RESET}"
                fi
            else
                warn "'whois' not installed. Install for better detection."
            fi
        fi
    fi

    # Additional checks
    echo -e ""
    echo -e "  ${BCYAN}━━━ Environment Checks ─━━${RESET}"

    # Check for VPN interfaces
    local vpn_ifaces=()
    if check_command "ip"; then
        for iface in $(ip link show 2>/dev/null | grep -oP '^\d+:\s+\K[^:]+' ); do
            case "$iface" in
                tun*|tap*|wg*|vpn*|ppp*) vpn_ifaces+=("$iface") ;;
            esac
        done
    fi

    if [[ ${#vpn_ifaces[@]} -gt 0 ]]; then
        echo -e "  ${BYELLOW}🛡️  VPN Interfaces Found:${RESET}"
        for vi in "${vpn_ifaces[@]}"; do
            echo -e "     ${BMAGENTA}➜${RESET} ${YELLOW}${vi}${RESET}"
        done
    else
        echo -e "  ${BGREEN}🔗 No VPN interfaces detected.${RESET}"
    fi

    # Check proxy environment variables
    local proxy_vars=()
    for pvar in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY socks_proxy SOCKS_PROXY; do
        if [[ -n "${!pvar:-}" ]]; then
            proxy_vars+=("${pvar}=${!pvar}")
        fi
    done

    if [[ ${#proxy_vars[@]} -gt 0 ]]; then
        echo -e "  ${BYELLOW}🔄 Proxy Environment Variables Found:${RESET}"
        for pv in "${proxy_vars[@]}"; do
            echo -e "     ${BMAGENTA}➜${RESET} ${YELLOW}${pv}${RESET}"
        done
    else
        echo -e "  ${BGREEN}🔓 No proxy environment variables set.${RESET}"
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📊 Feature 14: Network Summary Dashboard
# ──────────────────────────────────────────────
network_dashboard() {
    print_header
    echo -e "  ${BG_BLUE}${BWHITE}           📊 NETWORK SUMMARY DASHBOARD 📊            ${RESET}"
    print_separator
    echo -e ""

    # ── Internet Status ──
    if check_internet; then
        echo -e "  ${BGREEN}━━━ Internet Status ━━━${RESET}"
        echo -e "  ${BGREEN}  ● CONNECTED${RESET}"
    else
        echo -e "  ${BRED}━━━ Internet Status ━━━${RESET}"
        echo -e "  ${BRED}  ● DISCONNECTED${RESET}"
    fi

    echo -e ""

    # ── Public IP ──
    echo -e "  ${BCYAN}━━━ Public Network ━━━${RESET}"
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 "https://api.ipify.org" 2>/dev/null || echo "")
    fi
    if [[ -n "$PUBLIC_IP" ]]; then
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BGREEN}%s${RESET}\n" "Public IP" "$PUBLIC_IP"
    else
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BRED}Unavailable${RESET}\n" "Public IP"
    fi

    # Quick geo
    local quick_geo
    quick_geo=$(curl -s --max-time 5 "https://ipapi.co/json/" 2>/dev/null)
    if [[ -n "$quick_geo" ]] && ! echo "$quick_geo" | grep -qi "error\|rate"; then
        local q_city q_country q_tz q_isp
        q_city=$(echo "$quick_geo" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        q_country=$(echo "$quick_geo" | grep -oP '"country_name":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        q_tz=$(echo "$quick_geo" | grep -oP '"timezone":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        q_isp=$(echo "$quick_geo" | grep -oP '"org":\s*"\K[^"]+' 2>/dev/null || echo "N/A")
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BCYAN}%s, %s${RESET}\n" "Location" "$q_city" "$q_country"
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BYELLOW}%s${RESET}\n" "Timezone" "$q_tz"
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BWHITE}%s${RESET}\n" "ISP" "$q_isp"
    fi

    echo -e ""

    # ── Local Network ──
    echo -e "  ${BMAGENTA}━━━ Local Network ━━━${RESET}"
    printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BGREEN}%s${RESET}\n" "Hostname" "$(hostname 2>/dev/null || echo 'N/A')"

    if [[ -z "$LOCAL_IP" ]]; then
        if check_command "ip"; then
            LOCAL_IP=$(ip -4 addr show 2>/dev/null | grep -oP 'inet\s+\K[^/]+' | grep -v '^127\.' | head -1 || echo "")
        fi
    fi
    printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BGREEN}%s${RESET}\n" "Local IP" "${LOCAL_IP:-N/A}"

    # Gateway
    local gw_ip
    if check_command "ip"; then
        gw_ip=$(ip route show default 2>/dev/null | grep -oP 'via\s+\K[^ ]+' || echo "")
    fi
    printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BYELLOW}%s${RESET}\n" "Gateway" "${gw_ip:-N/A}"

    # DNS
    local dns1=""
    if [[ -f /etc/resolv.conf ]]; then
        dns1=$(grep -E '^\s*nameserver' /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
    fi
    printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BCYAN}%s${RESET}\n" "DNS Server" "${dns1:-N/A}"

    echo -e ""

    # ── Interfaces ──
    echo -e "  ${BYELLOW}━━━ Active Interfaces ━━━${RESET}"
    if check_command "ip"; then
        ip -brief addr show 2>/dev/null | while IFS= read -r line; do
            local iface status ip_info
            iface=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            ip_info=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^ *//')
            if [[ "$status" == "UP" || "$status" == "UNKNOWN" ]]; then
                if [[ -n "$ip_info" ]]; then
                    printf "  ${BGREEN}●${RESET} ${BWHITE}%-14s${RESET} ${DIM}${ip_info}${RESET}\n" "$iface"
                else
                    printf "  ${BGREEN}●${RESET} ${BWHITE}%-14s${RESET} ${DIM}no address${RESET}\n" "$iface"
                fi
            fi
        done
    fi

    echo -e ""

    # ── Listening Ports Summary ──
    echo -e "  ${BRED}━━━ Listening Ports Summary ━━━${RESET}"
    if check_command "ss"; then
        local tcp_cnt udp_cnt
        tcp_cnt=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l)
        udp_cnt=$(ss -ulnp 2>/dev/null | tail -n +2 | wc -l)
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BGREEN}%s${RESET}\n" "TCP Ports Open" "$tcp_cnt"
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BMAGENTA}%s${RESET}\n" "UDP Ports Open" "$udp_cnt"

        # Show top interesting ports
        echo -e ""
        info "Notable Ports:"
        local interesting_ports=(22 80 443 3306 5432 6379 8080 8443 27017)
        for port in "${interesting_ports[@]}"; do
            if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                local proc
                proc=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | grep -oP 'users:\(\("\K[^"]+' || echo "")
                printf "  ${BGREEN}◆${RESET} Port %-6s ${GREEN}OPEN${RESET}  ${DIM}%s${RESET}\n" "$port" "$proc"
            fi
        done
    elif check_command "netstat"; then
        local tcp_cnt udp_cnt
        tcp_cnt=$(netstat -tlnp 2>/dev/null | tail -n +2 | wc -l)
        udp_cnt=$(netstat -ulnp 2>/dev/null | tail -n +2 | wc -l)
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BGREEN}%s${RESET}\n" "TCP Ports Open" "$tcp_cnt"
        printf "  ${BWHITE}%-20s${RESET} ${DIM}:${RESET} ${BMAGENTA}%s${RESET}\n" "UDP Ports Open" "$udp_cnt"
    else
        printf "  ${DIM}%-20s${RESET} ${DIM}:${RESET} ${DIM}ss/netstat not available${RESET}\n" "Port Info"
    fi

    echo -e ""

    # ── Latency Check ──
    echo -e "  ${BCYAN}━━━ Quick Latency Check ━━━${RESET}"
    local latency_targets=("google.com" "cloudflare.com")
    for target in "${latency_targets[@]}"; do
        local lat
        lat=$(ping -c 1 -W 3 "$target" 2>/dev/null | grep -oP 'time=\K[0-9.]+' || echo "timeout")
        if [[ "$lat" != "timeout" ]]; then
            if (( $(echo "$lat < 30" | bc -l 2>/dev/null || echo 0) )); then
                printf "  ${BGREEN}◆${RESET} %-20s ${BGREEN}%s ms${RESET}  ${DIM}(Excellent)${RESET}\n" "$target" "$lat"
            elif (( $(echo "$lat < 100" | bc -l 2>/dev/null || echo 0) )); then
                printf "  ${BYELLOW}◆${RESET} %-20s ${BYELLOW}%s ms${RESET}  ${DIM}(Good)${RESET}\n" "$target" "$lat"
            else
                printf "  ${BRED}◆${RESET} %-20s ${BRED}%s ms${RESET}  ${DIM}(High)${RESET}\n" "$target" "$lat"
            fi
        else
            printf "  ${BRED}✖${RESET} %-20s ${RED}timeout${RESET}\n" "$target"
        fi
    done

    echo -e ""
    print_separator
    echo -e "  ${DIM}Dashboard generated at: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    print_separator

    wait_for_key
}

# ──────────────────────────────────────────────
# 💾 Feature 15: Save Report
# ──────────────────────────────────────────────
save_report() {
    print_section "💾 Save Report to File"

    local report="$REPORT_FILE"

    prompt "Enter filename [default: ${report}]: "
    local custom_name
    read -r custom_name
    if [[ -n "$custom_name" ]]; then
        report="$custom_name"
    fi

    echo -e ""
    info "Generating comprehensive report..."
    echo -e ""

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "  🌍 NETWORK INFORMATION REPORT"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "  Tool: $SCRIPT_NAME v$VERSION"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🖥️  SYSTEM INFORMATION"
        echo "───────────────────────────────────────────────────────────────"
        echo "  Hostname:     $(hostname 2>/dev/null || echo 'N/A')"
        echo "  FQDN:         $(hostname -f 2>/dev/null || echo 'N/A')"
        echo "  OS:           $(uname -s) $(uname -r) $(uname -m)"
        if [[ -f /etc/os-release ]]; then
            echo "  Distribution: $(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo 'N/A')"
        fi
        echo "  User:         $(whoami)"
        echo "  Date:         $(date)"
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🌐 PUBLIC IP INFORMATION"
        echo "───────────────────────────────────────────────────────────────"
        if [[ -z "$PUBLIC_IP" ]]; then
            PUBLIC_IP=$(curl -s --max-time 5 "https://api.ipify.org" 2>/dev/null || echo "Unavailable")
        fi
        echo "  Public IP: $PUBLIC_IP"

        local geo_data
        geo_data=$(curl -s --max-time 10 "https://ipapi.co/json/" 2>/dev/null)
        if [[ -n "$geo_data" ]] && ! echo "$geo_data" | grep -qi "error\|rate"; then
            echo "  City:        $(echo "$geo_data" | grep -oP '"city":\s*"\K[^"]+' || echo 'N/A')"
            echo "  Region:      $(echo "$geo_data" | grep -oP '"region":\s*"\K[^"]+' || echo 'N/A')"
            echo "  Country:     $(echo "$geo_data" | grep -oP '"country_name":\s*"\K[^"]+' || echo 'N/A') ($(echo "$geo_data" | grep -oP '"country_code":\s*"\K[^"]+' || echo 'N/A'))"
            echo "  Postal:      $(echo "$geo_data" | grep -oP '"postal":\s*"\K[^"]+' || echo 'N/A')"
            echo "  Latitude:    $(echo "$geo_data" | grep -oP '"latitude":\s*\K[^,]+' || echo 'N/A')"
            echo "  Longitude:   $(echo "$geo_data" | grep -oP '"longitude":\s*\K[^,]+' || echo 'N/A')"
            echo "  Timezone:    $(echo "$geo_data" | grep -oP '"timezone":\s*"\K[^"]+' || echo 'N/A')"
            echo "  ISP/Org:     $(echo "$geo_data" | grep -oP '"org":\s*"\K[^"]+' || echo 'N/A')"
            echo "  ASN:         $(echo "$geo_data" | grep -oP '"asn":\s*"\K[^"]+' || echo 'N/A')"
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🏠 LOCAL NETWORK INFORMATION"
        echo "───────────────────────────────────────────────────────────────"
        if check_command "ip"; then
            echo "  Local Interfaces:"
            ip -4 addr show 2>/dev/null | grep -E "^[0-9]+:|inet " | while IFS= read -r line; do
                if [[ "$line" =~ ^[0-9]+: ]]; then
                    local ifname
                    ifname=$(echo "$line" | grep -oP '^\d+:\s+\K[^:]+' || echo "")
                    echo ""
                    echo "    Interface: $ifname"
                elif [[ "$line" =~ inet ]]; then
                    local ipaddr netmask
                    ipaddr=$(echo "$line" | grep -oP 'inet\s+\K[^/]+' || echo "")
                    echo "    IP Address: $ipaddr"
                fi
            done
            echo ""
            echo "  Default Gateway:"
            ip route show default 2>/dev/null | while IFS= read -r route; do
                echo "    $route"
            done
        elif check_command "ifconfig"; then
            ifconfig 2>/dev/null
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🌍 DNS SERVERS"
        echo "───────────────────────────────────────────────────────────────"
        if [[ -f /etc/resolv.conf ]]; then
            grep -E '^\s*nameserver' /etc/resolv.conf 2>/dev/null | while IFS= read -r line; do
                echo "  $line"
            done
        fi
        if check_command "resolvectl"; then
            resolvectl status 2>/dev/null | grep "DNS Servers" | while IFS= read -r line; do
                echo "  $line"
            done
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🚪 LISTENING PORTS"
        echo "───────────────────────────────────────────────────────────────"
        if check_command "ss"; then
            echo "  TCP:"
            ss -tlnp 2>/dev/null | while IFS= read -r line; do
                echo "  $line"
            done
            echo ""
            echo "  UDP:"
            ss -ulnp 2>/dev/null | while IFS= read -r line; do
                echo "  $line"
            done
        elif check_command "netstat"; then
            netstat -tlnp 2>/dev/null
            echo ""
            netstat -ulnp 2>/dev/null
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  📡 ROUTING TABLE"
        echo "───────────────────────────────────────────────────────────────"
        if check_command "ip"; then
            ip route show 2>/dev/null | while IFS= read -r route; do
                echo "  $route"
            done
        elif check_command "route"; then
            route -n 2>/dev/null
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  📶 CONNECTIVITY TEST"
        echo "───────────────────────────────────────────────────────────────"
        local test_hosts=("google.com" "cloudflare.com" "github.com" "amazon.com")
        for host in "${test_hosts[@]}"; do
            local result
            if ping -c 1 -W 3 "$host" &>/dev/null; then
                local lat
                lat=$(ping -c 1 -W 3 "$host" 2>/dev/null | grep -oP 'time=\K[0-9.]+' || echo "?")
                result="REACHABLE (${lat}ms)"
            else
                result="UNREACHABLE"
            fi
            printf "  %-25s %s\n" "$host" "$result"
        done
        echo ""

        echo "───────────────────────────────────────────────────────────────"
        echo "  🔒 VPN/PROXY CHECK"
        echo "───────────────────────────────────────────────────────────────"
        local vpn_check
        vpn_check=$(curl -s --max-time 10 "http://ip-api.com/json/?fields=proxy,hosting" 2>/dev/null)
        if [[ -n "$vpn_check" ]]; then
            local is_proxy is_hosting
            is_proxy=$(echo "$vpn_check" | grep -oP '"proxy":\s*\K[^,}]+' || echo "unknown")
            is_hosting=$(echo "$vpn_check" | grep -oP '"hosting":\s*\K[^,}]+' || echo "unknown")
            echo "  Proxy Detected:  $is_proxy"
            echo "  Hosting/Datacenter: $is_hosting"
        else
            echo "  Could not perform VPN/Proxy check."
        fi

        # Check VPN interfaces
        echo ""
        echo "  VPN Interfaces:"
        local found_vpn=false
        if check_command "ip"; then
            for iface in $(ip link show 2>/dev/null | grep -oP '^\d+:\s+\K[^:]+'); do
                case "$iface" in
                    tun*|tap*|wg*|vpn*|ppp*)
                        echo "    - $iface (detected)"
                        found_vpn=true
                        ;;
                esac
            done
        fi
        [[ "$found_vpn" == "false" ]] && echo "    None detected"

        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  END OF REPORT"
        echo "═══════════════════════════════════════════════════════════════"
    } > "$report" 2>&1

    if [[ -f "$report" ]]; then
        local file_size
        file_size=$(du -h "$report" 2>/dev/null | cut -f1)
        local file_path
        file_path=$(realpath "$report" 2>/dev/null || echo "$report")
        echo -e "  ┌──────────────────────────────────────────────┐"
        echo -e "  │${BGREEN}  💾 Report Saved Successfully!                ${RESET}│"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  │${BWHITE}  📄 File: ${BYELLOW}${report}${BWHITE}                    ${RESET}│"
        echo -e "  │${BWHITE}  📁 Path: ${CYAN}${file_path}${BWHITE}  ${RESET}│"
        echo -e "  │${BWHITE}  📊 Size: ${GREEN}${file_size}${BWHITE}                              ${RESET}│"
        echo -e "  │${BGREEN}                                              ${RESET}│"
        echo -e "  └──────────────────────────────────────────────┘"
    else
        error "Failed to save report!"
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🔧 Feature 16: ARP Table
# ──────────────────────────────────────────────
show_arp_table() {
    print_section "🔗 ARP Table"

    if check_command "ip"; then
        ip neigh show 2>/dev/null | while IFS= read -r line; do
            local ip mac state dev
            ip=$(echo "$line" | awk '{print $1}')
            dev=$(echo "$line" | grep -oP 'dev\s+\K[^ ]+' || echo "")
            state=$(echo "$line" | grep -oP '\K[A-Z]+$' || echo "")
            mac=$(echo "$line" | awk '{print $2}')

            if [[ "$mac" == "<incomplete>" ]]; then
                printf "  ${BRED}✖${RESET} %-18s ${RED}%s${RESET}  %-6s %s\n" "$ip" "$mac" "$state" "$dev"
            elif [[ "$state" == "REACHABLE" || "$state" == "STALE" ]]; then
                printf "  ${BGREEN}◆${RESET} %-18s ${BMAGENTA}%s${RESET}  ${GREEN}%-8s${RESET} %s\n" "$ip" "$mac" "$state" "$dev"
            else
                printf "  ${BYELLOW}◆${RESET} %-18s ${BMAGENTA}%s${RESET}  ${YELLOW}%-8s${RESET} %s\n" "$ip" "$mac" "$state" "$dev"
            fi
        done
    elif check_command "arp"; then
        arp -a 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done
    else
        error "Neither 'ip' nor 'arp' command found."
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📡 Feature 17: Wireless Info
# ──────────────────────────────────────────────
show_wireless() {
    print_section "📡 Wireless Information"

    local wifi_iface=""

    # Find wireless interface
    if check_command "iwconfig"; then
        wifi_iface=$(iwconfig 2>/dev/null | grep -oP '^\K[a-zA-Z0-9]+' | head -1)
    elif [[ -d /sys/class/net ]]; then
        for iface in /sys/class/net/*; do
            if [[ -f "$iface/wireless" ]] || [[ -d "$iface/phy80211" ]]; then
                wifi_iface=$(basename "$iface")
                break
            fi
        done
    fi

    if [[ -z "$wifi_iface" ]]; then
        warn "No wireless interface detected."
        wait_for_key
        return
    fi

    info "Wireless Interface: ${BYELLOW}${wifi_iface}${CYAN}"
    echo -e ""

    # iwconfig details
    if check_command "iwconfig"; then
        iwconfig "$wifi_iface" 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${WHITE}${line}${RESET}"
        done
    fi

    # iw details
    if check_command "iw"; then
        echo -e ""
        info "Connection Details (iw):"
        iw dev "$wifi_iface" link 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${CYAN}${line}${RESET}"
        done

        echo -e ""
        info "Supported Frequencies:"
        iw list 2>/dev/null | grep -A 20 "Frequencies:" | head -25 | while IFS= read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done
    fi

    # Signal strength from /proc/net/wireless
    if [[ -f /proc/net/wireless ]]; then
        echo -e ""
        info "Signal from /proc/net/wireless:"
        echo -e ""
        printf "  ${BWHITE}%-12s ${BWHITE}%-8s ${BWHITE}%-8s ${BWHITE}%-8s${RESET}\n" "Interface" "Status" "Link" "Level"
        print_thin_separator
        tail -n +3 /proc/net/wireless 2>/dev/null | while IFS= read -r line; do
            local wiface wstatus wlink wlevel wnoise
            wiface=$(echo "$line" | awk '{print $1}' | tr -d ':')
            wstatus=$(echo "$line" | awk '{print $2}')
            wlink=$(echo "$line" | awk '{print $3}')
            wlevel=$(echo "$line" | awk '{print $4}')
            wnoise=$(echo "$line" | awk '{print $5}')
            printf "  ${BCYAN}%-12s ${RESET}${GREEN}%-8s ${RESET}${BYELLOW}%-8s ${RESET}${BMAGENTA}%-8s${RESET}\n" \
                "$wiface" "$wstatus" "$wlink" "$wlevel"
        done
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 🧹 Feature 18: Network Reset Helper
# ──────────────────────────────────────────────
network_reset() {
    print_section "🧹 Network Reset Helper"

    echo -e "  ${DIM}This section provides common network reset commands.${RESET}"
    echo -e "  ${DIM}Commands will NOT be executed automatically.${RESET}"
    echo -e ""

    require_root

    echo -e "  ${BYELLOW}━━━ Flush DNS Cache ━━━${RESET}"
    echo -e "  ${DIM}# systemd-resolved:${RESET}"
    echo -e "  ${WHITE}sudo resolvectl flush-caches${RESET}"
    echo -e "  ${DIM}# nscd:${RESET}"
    echo -e "  ${WHITE}sudo nscd -i hosts${RESET}"
    echo -e "  ${DIM}# dnsmasq:${RESET}"
    echo -e "  ${WHITE}sudo systemctl restart dnsmasq${RESET}"
    echo -e ""

    echo -e "  ${BYELLOW}━━━ Reset Network Interface ━━━${RESET}"
    echo -e "  ${DIM}# Example for eth0:${RESET}"
    echo -e "  ${WHITE}sudo ip link set eth0 down${RESET}"
    echo -e "  ${WHITE}sudo ip link set eth0 up${RESET}"
    echo -e "  ${DIM}# Or via NetworkManager:${RESET}"
    echo -e "  ${WHITE}sudo nmcli networking off${RESET}"
    echo -e "  ${WHITE}sudo nmcli networking on${RESET}"
    echo -e ""

    echo -e "  ${BYELLOW}━━━ Release & Renew DHCP ━━━${RESET}"
    echo -e "  ${DIM}# dhclient:${RESET}"
    echo -e "  ${WHITE}sudo dhclient -r${RESET}"
    echo -e "  ${WHITE}sudo dhclient${RESET}"
    echo -e "  ${DIM}# NetworkManager:${RESET}"
    echo -e "  ${WHITE}sudo nmcli con down <connection-name>${RESET}"
    echo -e "  ${WHITE}sudo nmcli con up <connection-name>${RESET}"
    echo -e ""

    echo -e "  ${BYELLOW}━━━ Clear ARP Cache ━━━${RESET}"
    echo -e "  ${WHITE}sudo ip neigh flush all${RESET}"
    echo -e ""

    echo -e "  ${BYELLOW}━━━ Reset Routing Table ━━━${RESET}"
    echo -e "  ${WHITE}sudo ip route flush table main${RESET}"
    echo -e ""

    echo -e "  ${BYELLOW}━━━ Full Network Restart ━━━${RESET}"
    echo -e "  ${DIM}# systemd:${RESET}"
    echo -e "  ${WHITE}sudo systemctl restart NetworkManager${RESET}"
    echo -e "  ${DIM}# or:${RESET}"
    echo -e "  ${WHITE}sudo systemctl restart networking${RESET}"
    echo -e ""

    prompt "Execute 'sudo resolvectl flush-caches; sudo ip neigh flush all'? [y/N]: "
    local answer
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo -e ""
        info "Flushing DNS cache..."
        if sudo resolvectl flush-caches 2>&1; then
            success "DNS cache flushed."
        else
            warn "DNS flush may not have succeeded (resolvectl not available?)."
        fi
        info "Flushing ARP cache..."
        if sudo ip neigh flush all 2>&1; then
            success "ARP cache flushed."
        else
            error "ARP flush failed."
        fi
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📜 Feature 19: Connection Monitor (Live)
# ──────────────────────────────────────────────
connection_monitor() {
    print_section "📜 Live Connection Monitor"

    local duration=10
    prompt "Monitor duration in seconds [default: ${duration}]: "
    local input_dur
    read -r input_dur
    if [[ -n "$input_dur" && "$input_dur" =~ ^[0-9]+$ ]]; then
        duration="$input_dur"
    fi

    echo -e ""
    info "Monitoring connections for ${BYELLOW}${duration}${CYAN} seconds..."
    echo -e "  ${DIM}Press Ctrl+C to stop early.${RESET}"
    echo -e ""
    print_thin_separator

    local end_time=$((SECONDS + duration))
    local iteration=0

    while [[ $SECONDS -lt $end_time ]]; do
        iteration=$((iteration + 1))
        local remaining=$((end_time - SECONDS))

        # Clear line and print status
        printf "\r  ${BCYAN}[%02ds remaining]${RESET} " "$remaining"

        local tcp_established tcp_time_wait tcp_close_wait
        local udp_connections total_connections

        if check_command "ss"; then
            tcp_established=$(ss -tan state established 2>/dev/null | wc -l)
            tcp_time_wait=$(ss -tan state time-wait 2>/dev/null | wc -l)
            tcp_close_wait=$(ss -tan state close-wait 2>/dev/null | wc -l)
            udp_connections=$(ss -uan 2>/dev/null | wc -l)
            total_connections=$((tcp_established + tcp_time_wait + tcp_close_wait + udp_connections))
        elif check_command "netstat"; then
            tcp_established=$(netstat -tan 2>/dev/null | grep -c "ESTABLISHED" || echo 0)
            tcp_time_wait=$(netstat -tan 2>/dev/null | grep -c "TIME_WAIT" || echo 0)
            tcp_close_wait=$(netstat -tan 2>/dev/null | grep -c "CLOSE_WAIT" || echo 0)
            udp_connections=$(netstat -uan 2>/dev/null | tail -n +2 | wc -l)
            total_connections=$((tcp_established + tcp_time_wait + tcp_close_wait + udp_connections))
        else
            error "Neither 'ss' nor 'netstat' available."
            break
        fi

        printf "${BGREEN}EST:%-4d${RESET} ${BYELLOW}TW:%-4d${RESET} ${BRED}CW:%-4d${RESET} ${BMAGENTA}UDP:%-4d${RESET} ${BWHITE}TOT:%-4d${RESET}" \
            "$tcp_established" "$tcp_time_wait" "$tcp_close_wait" "$udp_connections" "$total_connections"

        sleep 1
    done

    echo -e ""
    echo -e ""
    print_thin_separator
    echo -e ""
    info "Final Connection State:"
    echo -e ""

    if check_command "ss"; then
        echo -e "  ${BGREEN}━━━ ESTABLISHED Connections (top 15) ━━━${RESET}"
        ss -tanp state established 2>/dev/null | tail -n +2 | head -15 | while IFS= read -r line; do
            local src dst proc
            src=$(echo "$line" | awk '{print $4}')
            dst=$(echo "$line" | awk '{print $5}')
            proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' 2>/dev/null || echo "")
            printf "  ${BGREEN}◆${RESET} ${DIM}%-25s → %-25s${RESET} ${YELLOW}%s${RESET}\n" "$src" "$dst" "$proc"
        done

        echo -e ""
        echo -e "  ${BYELLOW}━━━ TIME_WAIT Connections ━━━${RESET}"
        local tw_count
        tw_count=$(ss -tan state time-wait 2>/dev/null | tail -n +2 | wc -l)
        echo -e "  ${BYELLOW}◆${RESET} ${YELLOW}${tw_count} connections in TIME_WAIT state${RESET}"

        echo -e ""
        echo -e "  ${BRED}━━━ CLOSE_WAIT Connections ━━━${RESET}"
        ss -tanp state close-wait 2>/dev/null | tail -n +2 | while IFS= read -r line; do
            local src dst proc
            src=$(echo "$line" | awk '{print $4}')
            dst=$(echo "$line" | awk '{print $5}')
            proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' 2>/dev/null || echo "")
            printf "  ${BRED}◆${RESET} ${RED}%-25s → %-25s${RESET} ${YELLOW}%s${RESET}\n" "$src" "$dst" "$proc"
        done
    fi

    wait_for_key
}

# ──────────────────────────────────────────────
# 📖 Feature 20: About / Help
# ──────────────────────────────────────────────
show_about() {
    print_section "📖 About & Help"

    echo -e "  ${BCYAN}🌍 IP & Network Information Tool${RESET} ${DIM}v${VERSION}${RESET}"
    echo -e ""
    echo -e "  ${BWHITE}A comprehensive CLI tool for network diagnostics,${RESET}"
    echo -e "  ${BWHITE}information gathering, and troubleshooting.${RESET}"
    echo -e ""
    print_thin_separator
    echo -e ""
    echo -e "  ${BYELLOW}💡 Tips:${RESET}"
    echo -e "  ${DIM}• Some features require root (sudo) for full output${RESET}"
    echo -e "  ${DIM}• Geolocation uses free APIs (ipapi.co, ipinfo.io)${RESET}"
    echo -e "  ${DIM}• Speed test uses curl download estimation${RESET}"
    echo -e "  ${DIM}• Install 'speedtest-cli' for accurate speed tests${RESET}"
    echo -e "  ${DIM}• Install 'traceroute' if not available${RESET}"
    echo -e "  ${DIM}• Reports are saved in the current directory${RESET}"
    echo -e ""
    echo -e "  ${BYELLOW}🔧 Suggested packages:${RESET}"
    echo -e "  ${WHITE}  sudo apt install iproute2 iputils-ping traceroute${RESET}"
    echo -e "  ${WHITE}  sudo apt install dnsutils net-tools whois curl${RESET}"
    echo -e "  ${WHITE}  sudo apt install wireless-tools iw bc${RESET}"
    echo -e "  ${WHITE}  pip3 install speedtest-cli${RESET}"
    echo -e ""
    echo -e "  ${BYELLOW}⚠️  Disclaimer:${RESET}"
    echo -e "  ${DIM}This tool is for legitimate network diagnostics only.${RESET}"
    echo -e "  ${DIM}Respect privacy and comply with local regulations.${RESET}"
    echo -e ""
    print_thin_separator

    wait_for_key
}

# ──────────────────────────────────────────────
# 🎨 Main Menu
# ──────────────────────────────────────────────
show_menu() {
    print_header

    local menu_items=(
        "🌐  Show Public IP Address"
        "📍  IP Geolocation"
        "🏠  Show Local IP Address"
        "🖥️  Display Hostname"
        "📡  Network Interface Details"
        "🚪  Default Gateway & Routes"
        "🌍  DNS Servers"
        "📶  Ping Any Host"
        "🔍  DNS Lookup"
        "🌐  Traceroute"
        "🚪  Check Open Ports"
        "⚡  Internet Speed Test"
        "🔒  VPN/Proxy Detection"
        "📊  Network Summary Dashboard"
        "🔗  ARP Table"
        "📡  Wireless Information"
        "📜  Live Connection Monitor"
        "🧹  Network Reset Helper"
        "💾  Save Report to File"
        "📖  About & Help"
    )

    echo -e "  ${BWHITE}┌─────────────────────────────────────────────────────┐${RESET}"
    echo -e "  ${BWHITE}│${RESET}             ${BG_YELLOW}${BBLACK} SELECT AN OPTION ${RESET}${BWHITE}                  │${RESET}"
    echo -e "  ${BWHITE}└─────────────────────────────────────────────────────┘${RESET}"
    echo -e ""

    local i=1
    for item in "${menu_items[@]}"; do
        local num
        if [[ $i -lt 10 ]]; then
            num=" ${i}"
        else
            num="$i"
        fi
        echo -e "  ${BG_BLUE}${BBLACK} ${num} ${RESET}  ${BWHITE}${item}${RESET}"
        i=$((i + 1))
    done

    echo -e ""
    echo -e "  ${BRED}  0  Exit${RESET}"
    echo -e ""
    print_thin_separator
}

main() {
    # Check basic dependencies
    local missing=()
    for cmd in curl ping; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${BRED}⚠  Missing required commands: ${missing[*]}${RESET}"
        echo -e "${YELLOW}Please install them before running this tool.${RESET}"
        echo -e ""
        echo -e "${DIM}  sudo apt install curl iputils-ping${RESET}"
        exit 1
    fi

    while true; do
        show_menu

        prompt "Enter choice [0-20]: "
        local choice
        read -r choice

        case "$choice" in
            1)  get_public_ip ;;
            2)  get_geolocation ;;
            3)  get_local_ip ;;
            4)  show_hostname ;;
            5)  show_interfaces ;;
            6)  show_gateway ;;
            7)  show_dns ;;
            8)  ping_host ;;
            9)  dns_lookup ;;
            10) traceroute_host ;;
            11) check_ports ;;
            12) speed_test ;;
            13) vpn_proxy_detect ;;
            14) network_dashboard ;;
            15) show_arp_table ;;
            16) show_wireless ;;
            17) connection_monitor ;;
            18) network_reset ;;
            19) save_report ;;
            20) show_about ;;
            0|q|Q|exit|quit)
                echo -e ""
                echo -e "  ${BGREEN}✓ Goodbye! Stay connected. 🌍${RESET}"
                echo -e ""
                exit 0
                ;;
            *)
                error "Invalid option: '$choice'. Please enter 0-20."
                sleep 1
                ;;
        esac
    done
}

# ──────────────────────────────────────────────
# 🚀 Entry Point
# ──────────────────────────────────────────────
main "$@"