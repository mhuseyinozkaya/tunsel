#!/usr/bin/env bash

check_root(){
    if [ "$(id -u)" -ne 0 ]; then
        echo "[!] Script requires privilege permission (use sudo)"
        exit 1
    fi
}

check_root

DEFAULT_WORKDIR="/usr/local/lib/tunsel"
mkdir -p "$DEFAULT_WORKDIR"

WG_DIR="$DEFAULT_WORKDIR/wireguard"
mkdir -p "$WG_DIR"

OVPN_DIR="$DEFAULT_WORKDIR/openvpn"
mkdir -p "$OVPN_DIR"

WG_STATE="$DEFAULT_WORKDIR/active_wg.state"
OVPN_PID="$DEFAULT_WORKDIR/active_ovpn.pid"

ARGS=("$@")
ARGS_COUNT="$#"

#   Argument parsing
argument_parser(){
    if [[ "$ARGS_COUNT" -eq 1 && "${ARGS[$ARGS_COUNT-1]}" == "wconnect" ]];then
        connect_tunnel "$WG_DIR"
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[$ARGS_COUNT-1]}" == "oconnect" ]];then
        connect_tunnel "$OVPN_DIR"
    elif [[ "$ARGS_COUNT" -eq 1 && "${ARGS[$ARGS_COUNT-1]}" == "disconnect" ]];then
        disconnect_tunnel
    elif [[ "$ARGS_COUNT" -eq 2 && "${ARGS[0]}" == "import" && -s "$(realpath "${ARGS[1]}")" ]];then
        import_tunnel_file "${ARGS[1]}"
    fi
}

import_tunnel_file(){
    local FILE_NAME="$1"
    local FILE_REALPATH="$(realpath "$FILE_NAME" 2>/dev/null)"

    if [[ -f "$FILE_REALPATH" ]];then
        if [[ "$FILE_REALPATH" == *.conf ]];then
            cp "$FILE_REALPATH" "$WG_DIR"
            echo "[+] Tunnel file successfully imported"
            exit
        elif [[ "$FILE_REALPATH" == *.ovpn ]];then
            cp "$FILE_REALPATH" "$OVPN_DIR"
            echo "[+] Tunnel file successfully imported"
            exit
        else
            echo "Unknown file type, only .ovpn and .conf are supported"
            exit
        fi
    else
        echo "[!] Import failed"
        exit
    fi
}

list_tunnels(){
    local DIR_NAME="$1"
    shopt -s nullglob
    # Create global tunnels list
    if [[ "$DIR_NAME" == "$WG_DIR" ]];then
        tunnels=("$DIR_NAME"/*.conf)
    else
        tunnels=("$DIR_NAME"/*.ovpn)
    fi
    shopt -u nullglob

    if [[ ${#tunnels[@]} -eq 0 ]];then
        echo "[!] No tunnel file found to connect"
        exit
    fi

    echo "Available tunnel profiles:"
    for i in "${!tunnels[@]}"; do
        echo "$((i + 1)). $(basename "${tunnels[i]}")"
    done
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

    if [[ "$software" == "$WG_DIR" ]];then
        if wg-quick up "${tunnels[$value-1]}" 1>/dev/null 2>&1; then
            echo "${tunnels[$value-1]}" > "$WG_STATE"
            echo "[+] Successfully connected to $(basename "${tunnels[$value-1]}") tunnel."
        fi
    elif [[ "$software" == "$OVPN_DIR" ]];then
        local ovpn_pid=""
        if openvpn --config "${tunnels[$value-1]}" --daemon --writepid "$OVPN_PID";then
            echo "[+] Successfully connected to $(basename "${tunnels[$value-1]}") tunnel."
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
            echo "[-] You successfully disconnected from OpenVPN interface."
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