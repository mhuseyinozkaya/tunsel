# tunsel
Tunnel selector for Wireguard and OpenVPN protocols

## Installation
Type the following command in your terminal to clone the repository 
```bash
git clone https://github.com/mhuseyinozkaya/tunsel.git
```

If the script is not executable type this too
```bash
chmod +x main.sh
```

## Usage
The script needs privilege permission to run, use sudo

If you use the script easily, you can install script with
```bash
sudo ./main.sh install
```

or you can uninstall it whenever you want
```bash
sudo tunsel uninstall
```

Example usage of the script
```bash
sudo tunsel wconnect # Connects Wireguard tunnel from available tunnel list

sudo tunsel oconnect # Connects OpenVPN tunnel from available tunnel list

sudo tunsel disconnect # Disconnect from tunnel

sudo tunsel import [..FILE(s)..] # Imports one or more tunnel file
# e.g sudo tunsel import foo.conf bar.ovpn

sudo tunsel status # Shows status

sudo tunsel list # Shows all imported tunnels
```
