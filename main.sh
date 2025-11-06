#!/usr/bin/env bash

check_root(){
    if [ "$(id -u)" -ne 0 ];then
        echo "[!] Script requires privilege permission (use sudo)"
        exit 1
    fi
}

check_root

SCRIPT_NAME="tunsel"

DEFAULT_WORKDIR="/usr/local/etc/$SCRIPT_NAME"
mkdir -p "$DEFAULT_WORKDIR"

WG_DIR="$DEFAULT_WORKDIR/wireguard"
mkdir -p "$WG_DIR"

OVPN_DIR="$DEFAULT_WORKDIR/openvpn"
mkdir -p "$OVPN_DIR"

WG_STATE="$DEFAULT_WORKDIR/active_wg.state"
OVPN_PID="$DEFAULT_WORKDIR/active_ovpn.pid"

ARGS=("$@")
ARGS_COUNT="$#"

info(){
    echo "$SCRIPT_NAME - Tunnel selector for Wireguard and OpenVPN protocols"
}

#   Argument parsing
argument_parser(){
    if [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "wconnect" ]];then
        connect_tunnel "$WG_DIR"
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "oconnect" ]];then
        connect_tunnel "$OVPN_DIR"
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "disconnect" ]];then
        disconnect_tunnel
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "status" ]];then
        connection_status
    elif [[ "$ARGS_COUNT" -ge 2 && "${ARGS[0]}" == "import" ]];then
        import_tunnel_file "${ARGS[@]:1}"    
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[0]}" == "list" ]];then
        list_tunnels
    elif [[ "$ARGS_COUNT" -eq 0 ]];then
        info
    else
        echo "[!] Unknown usage, for help use $0 help"
    fi
}

connection_status(){
    local up_epoch current_epoch connection_epoch formatted_up_time interface
    if [[ -s "$WG_STATE" ]];then
        connection_epoch=$(stat -c %Y "$WG_STATE")
        interface="Wireguard: $(< $WG_STATE)"
    elif [[ -s "$OVPN_PID" ]];then
        connection_epoch=$(stat -c %Y "$OVPN_PID")
        interface="OpenVPN PID: $(< $OVPN_PID)"
    else
        echo "[*] Status: Disconnected"
        return 
    fi
    current_epoch=$(date +%s)
    up_epoch=$((current_epoch - connection_epoch))
    formatted_up_time=$(date -u -d "@$up_epoch" +'%H:%M:%S')
    echo "[*] Status: Connected, Uptime: $formatted_up_time"
    echo "[*] Tunnel: $interface"
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
                echo "[+] Wireguard tunnel $(basename "$file_realpath") successfully imported"
            elif [[ "$file_realpath" == *.ovpn ]];then
                cp "$file_realpath" "$OVPN_DIR"
                echo "[+] OpenVPN tunnel $(basename "$file_realpath") successfully imported"
            else
                echo "[!] Unknown file type for $(basename "$file_realpath"), only .ovpn and .conf supported"
            fi
        else
            echo "[!] Import failed, file $(basename "$file_realpath") not found or empty"
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
        echo "[!] No tunnel file found to connect"
        exit 1
    fi

    # Print messages
    echo "$message"

    for i in "${!tunnels[@]}"; do
        echo "$((i + 1)). $(basename "${tunnels[i]}")"
    done
    return 0
}

connect_tunnel(){
    if [[ -s "$WG_STATE" || -s "$OVPN_PID" ]];then
        if ! disconnect_tunnel;then
            echo "[!] Could not connected."
            exit 1
        fi
    fi
    local software="$1"
    list_tunnels "$software"
    read -rp "[*] Please specify a tunnel to connect: " value

    if ! [[ "$value" =~ ^[0-9]+$ ]];then
        echo "[!] Invalid input: Please enter a number."
        return 1
    fi
    
    if [[ "$value" -lt 1 || "$value" -gt ${#tunnels[@]} ]];then
        echo "[!] Invalid selection: Number out of range."
        return 1
    fi
    
    if [[ "$software" == "$WG_DIR" ]];then
        if wg-quick up "${tunnels[$value-1]}" 1>/dev/null 2>&1;then
            echo "${tunnels[$value-1]}" > "$WG_STATE"
            echo "[+] Successfully connected to Wireguard $(basename "${tunnels[$value-1]}") tunnel."
        fi
    elif [[ "$software" == "$OVPN_DIR" ]];then
        if openvpn --config "${tunnels[$value-1]}" --daemon --writepid "$OVPN_PID";then
            echo "[+] Successfully connected to OpenVPN tunnel with PID $(basename "${tunnels[$value-1]}")"
        fi
    fi
}

disconnect_tunnel(){
    if [[ -s "$WG_STATE" ]];then
        local iface="$(< "$WG_STATE")"
        if wg-quick down "$iface" 1>/dev/null;then
            rm -f "$WG_STATE"
            echo "[-] You successfully disconnected from Wireguard interface $iface."
        fi
    elif [[ -s "$OVPN_PID" ]];then
        local pid="$(< "$OVPN_PID")"
        if kill "$pid" 1>/dev/null;then
            rm -f "$OVPN_PID"
            echo "[-] You successfully disconnected from OpenVPN interface which PID $pid."
        fi
    else
        echo "[!] You already disconnected."
        return 1
    fi
    return 0
}

main(){
    argument_parser
    exit 0;    
}

main