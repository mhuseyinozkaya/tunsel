#!/usr/bin/env bash

color_support(){
    RESET="\033[0m"
    BLACK="\033[30m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    MAGENTA="\033[35m"
    CYAN="\033[36m"
    WHITE="\033[37m"
    if ! printf "%b" "$BLACK"; then
        RESET=""
        BLACK=""
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        MAGENTA=""
        CYAN=""
        WHITE=""
    fi
    printf "%b" "$RESET"
}

check_required_commands(){
    local reqs=("wg" "openvpn")
    local missing="false"
    
    for command in "${reqs[@]}"; do
        if ! command -v "$command" >/dev/null 2>&1;then
            missing="true"
            printf "%b[!] Dependency missing: The script needs %b%s%b to run%b\n" "$RED" "$YELLOW" "$command" "$RED" "$RESET"
        fi
    done
  
    if [[ "$missing" == "true" ]]; then
        printf "%b[!] Please install the missing dependencies and try again.%b\n" "$RED" "$RESET"
        exit 1
    fi
}

check_root(){
    if [ "$(id -u)" -ne 0 ];then
        printf "%b[!] Script requires privilege permission %b(use sudo)\n" "$RED" "$RESET"
        exit 1
    fi
}

SCRIPT_NAME="tunsel"
INSTALL_DIR="/usr/local/bin"

DEFAULT_WORKDIR="/usr/local/etc/$SCRIPT_NAME"
mkdir -p "$DEFAULT_WORKDIR"

WG_DIR="$DEFAULT_WORKDIR/wireguard"
mkdir -p "$WG_DIR"

OVPN_DIR="$DEFAULT_WORKDIR/openvpn"
mkdir -p "$OVPN_DIR"

WG_STATE_FILE="$DEFAULT_WORKDIR/active_wg.state"
OVPN_PID_FILE="$DEFAULT_WORKDIR/active_ovpn.pid"

ARGS=("$@")
ARGS_COUNT="$#"

info(){
    echo "$SCRIPT_NAME - Tunnel selector for Wireguard and OpenVPN protocols"
}

help_message(){
    info
    printf "\n"
    printf "%bUsage:%b %s <command>\n" "$YELLOW" "$RESET" "$SCRIPT_NAME"
    printf "\n"
    printf "%bAvailable Commands:%b\n" "$YELLOW" "$RESET"
    printf "  %b%-12s%b  - %bConnect to a Wireguard tunnel%b\n" "$CYAN" "wconnect" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bConnect to an OpenVPN tunnel%b\n" "$CYAN" "oconnect" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bDisconnect the active tunnel%b\n" "$CYAN" "disconnect" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bShow current connection status%b\n" "$CYAN" "status" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bImport tunnel config files (.conf or .ovpn)%b\n" "$CYAN" "import" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bList all imported tunnels%b\n" "$CYAN" "list" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bInstall the script to %s%b\n" "$CYAN" "install" "$RESET" "$WHITE" "$INSTALL_DIR/$SCRIPT_NAME" "$RESET"
    printf "  %b%-12s%b  - %bUninstall the script%b\n" "$CYAN" "uninstall" "$RESET" "$WHITE" "$RESET"
    printf "  %b%-12s%b  - %bShow this help message%b\n" "$CYAN" "help" "$RESET" "$WHITE" "$RESET"
}

install_script(){
    cp -f "$(realpath "$0")" "$INSTALL_DIR/$SCRIPT_NAME"
    printf "%b[+] %bScript successfully installed as %btunsel%b\n" "$GREEN" "$RESET" "$CYAN" "$RESET"
}

uninstall_script(){
    if ! [[ -s "$INSTALL_DIR/$SCRIPT_NAME" ]];then
        printf "%b[!] %bThe script is not installed already\n" "$RED" "$RESET"
        return
    fi
    rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    printf "%b[-] %bScript successfully uninstalled.\n" "$YELLOW" "$RESET"
}

print_usage(){
    printf "%b[!] %bUnknown usage, for help use %b%s help%b\n" "$RED" "$RESET" "$YELLOW" "$(basename "$0")" "$RESET"
}

#   Argument parsing
argument_parser(){
    if [[ "${ARGS[0]}" == "wconnect" ]];then
        if [[ "$ARGS_COUNT" -eq 2 ]] && [[ -f "${ARGS[1]}" ]];then
            connect_tunnel "$WG_DIR" "$(realpath "${ARGS[1]}")"
        elif [[ "$ARGS_COUNT" -eq 1 ]];then
            connect_tunnel "$WG_DIR"
        else
            print_usage
        fi
    elif [[ "${ARGS[0]}" == "oconnect" ]];then
        if [[ "$ARGS_COUNT" -eq 2 ]] && [[ -f "${ARGS[1]}" ]];then
            connect_tunnel "$OVPN_DIR" "$(realpath "${ARGS[1]}")" 
        elif [[ "$ARGS_COUNT" -eq 1 ]];then
            connect_tunnel "$OVPN_DIR"
        else
            print_usage
        fi
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "disconnect" ]];then
        disconnect_tunnel
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "status" ]];then
        connection_status
    elif [[ "$ARGS_COUNT" -ge 2 && "${ARGS[0]}" == "import" ]];then
        import_tunnel_file "${ARGS[@]:1}"    
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "list" ]];then
        list_tunnels
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "install" ]];then
        install_script
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "uninstall" ]];then
        uninstall_script
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "help" ]];then
        help_message
    elif [[ "$ARGS_COUNT" -eq 0 ]];then
        info
    else
        print_usage
    fi
}

connection_status(){
    local up_epoch current_epoch connection_epoch formatted_up_time interface
    if [[ -s "$WG_STATE_FILE" ]];then
        connection_epoch=$(stat -c %Y "$WG_STATE_FILE")
        interface="Wireguard: $(< $WG_STATE_FILE)"
    elif [[ -s "$OVPN_PID_FILE" ]];then
        connection_epoch=$(stat -c %Y "$OVPN_PID_FILE")
        interface="OpenVPN PID:$MAGENTA $(< $OVPN_PID_FILE)"
    else
        printf "%b[*] %bStatus: %bDisconnected%b\n" "$BLUE" "$RESET" "$YELLOW" "$RESET"
        return 
    fi
    current_epoch=$(date +%s)
    up_epoch=$((current_epoch - connection_epoch))
    formatted_up_time=$(date -u -d "@$up_epoch" +'%H:%M:%S')
    printf "%b[*]%b Status:%b Connected,%b Uptime: $formatted_up_time%b\n" "$BLUE" "$RESET" "$GREEN" "$YELLOW" "$RESET"
    printf "%b[*]%b Tunnel:%b $interface%b\n" "$BLUE" "$RESET" "$YELLOW" "$RESET"
    return 0
}

import_tunnel_file(){
    local FILES=("$@")
    local file_realpath
    for file in "${FILES[@]}";do
        file_realpath="$(realpath "$file" 2>/dev/null)"
        if [[ -s "$file_realpath" ]];then
            if [[ "$file_realpath" == *.conf ]];then
                cp "$file_realpath" "$WG_DIR"
                printf "%b[+]%b Wireguard tunnel %b%s%b successfully imported\n" "$GREEN" "$RESET" "$YELLOW" "$(basename "$file_realpath")" "$RESET"
            elif [[ "$file_realpath" == *.ovpn ]];then
                cp "$file_realpath" "$OVPN_DIR"
                printf "%b[+]%b OpenVPN tunnel %b%s%b successfully imported\n" "$GREEN" "$RESET" "$YELLOW" "$(basename "$file_realpath")" "$RESET"
            else
                printf "%b[!]%b Unknown file type for %b%s%b, only .conf and .ovpn extensions supported\n" "$RED" "$RESET" "$YELLOW" "$(basename "$file_realpath")" "$RESET"
            fi
        else
            printf "%b[!]%b Import failed, file %b%s%b not found or empty\n" "$RED" "$RESET" "$YELLOW" "$(basename "$file_realpath")" "$RESET"
        fi
    done
}

list_tunnels(){
    local DIR_NAME="$1"
    local message="Available all profiles:"
    shopt -s nullglob
    # Create global tunnels list
    if [[ "$DIR_NAME" == "$WG_DIR" ]];then
        tunnels=("$DIR_NAME"/*.conf)
        message="Wireguard profiles:"
    elif [[ "$DIR_NAME" == "$OVPN_DIR" ]];then
        tunnels=("$DIR_NAME"/*.ovpn)
        message="OpenVPN profiles:"
    else
        tunnels=("$WG_DIR"/*.conf "$OVPN_DIR"/*.ovpn)        
    fi
    shopt -u nullglob

    if [[ ${#tunnels[@]} -eq 0 ]];then
        printf "%b[!] No tunnel file found to connect%b\n" "$RED" "$RESET"
        exit 1
    fi

    # Print messages
    printf "%b%s%b\n" "$YELLOW" "$message" "$RESET"

    for i in "${!tunnels[@]}"; do
        printf "%d) %b%s%b\n" "$((i + 1))" "$YELLOW" "$(basename "${tunnels[i]}")" "$RESET"
    done
    return 0
}

connect_tunnel(){
    # disconnect from previous session
    if [[ -s "$WG_STATE_FILE" || -s "$OVPN_PID_FILE" ]];then
        if ! disconnect_tunnel;then
            printf "%b[!]%b Could not connect, previous session active.\n" "$RED" "$RESET"
            exit 1
        fi
    fi
    # define local variables
    local software="$1"
    local file="$2" # assign realpath of file to variable

    if [[ -z "$file" ]];then
        # that function creates global tunnels array at exit success
        list_tunnels "$software"
        read -rp "${BLUE}[*]${RESET} Please specify a tunnel to connect: " value
        if ! [[ "$value" =~ ^[0-9]+$ ]];then
            printf "%b[!] Invalid input: Please enter a number.%b\n" "$RED" "$RESET"
            return 1
        fi
    
        if [[ "$value" -lt 1 || "$value" -gt ${#tunnels[@]} ]];then
            printf "%b[!] Invalid selection: Number out of range.%b\n" "$RED" "$RESET"
            return 1
        fi
        file="${tunnels[$value-1]}"
    fi
    
    if [[ "$software" == "$WG_DIR" ]];then
        if wg-quick up "$file" 1>/dev/null;then
            echo "$file" > "$WG_STATE_FILE"
            printf "%b[+] Successfully connected to Wireguard %b%s%b tunnel.%b\n" "$GREEN" "$YELLOW" "$(basename "$file")" "$GREEN" "$RESET"
        else
            printf "%b[!] Could not connect, please check tunnel file.%b\n" "$RED" "$RESET"
        fi
    elif [[ "$software" == "$OVPN_DIR" ]];then
        if openvpn --config "$file" --daemon --writepid "$OVPN_PID_FILE";then
            printf "%b[+] Successfully connected to OpenVPN tunnel%b\n" "$GREEN" "$RESET"
        else
            printf "%b[!] Could not connect, please check tunnel file.%b\n" "$RED" "$RESET"
        fi
    fi
}

disconnect_tunnel(){
    if [[ -s "$WG_STATE_FILE" ]];then
        local iface="$(< "$WG_STATE_FILE")"
        if wg-quick down "$iface" 1>/dev/null;then
            rm -f "$WG_STATE_FILE"
            printf "%b[-] You successfully disconnected from Wireguard interface %b%s%b\n" "$YELLOW" "$WHITE" "$iface" "$RESET"
        fi
    elif [[ -s "$OVPN_PID_FILE" ]];then
        local pid="$(< "$OVPN_PID_FILE")"
        if kill "$pid" 1>/dev/null;then
            rm -f "$OVPN_PID_FILE"
            printf "%b[-] You successfully disconnected from OpenVPN interface which PID %b%d%b\n" "$YELLOW" "$WHITE" "$pid" "$RESET"
        fi
    else
        printf "%b[!] You already disconnected.%b\n" "$RED" "$RESET"
        return 1
    fi
    return 0
}

main(){
    color_support
    check_required_commands
    check_root
    argument_parser
    exit 0
}

main