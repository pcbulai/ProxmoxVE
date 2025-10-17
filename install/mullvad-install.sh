#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

debug_log() {
    echo "[DEBUG $(date '+%H:%M:%S')] $1" >&2
}

debug_log "Starting Mullvad installation script"

msg_info "Installing Mullvad + Tailscale Exit Node Setup"


msg_info "Installing required packages (wireguard-tools, iptables, curl, resolvconf)"
debug_log "Starting package installation"
for attempt in 1 2 3; do
    debug_log "Package installation attempt $attempt"
    if timeout 300 apt install -y wireguard-tools iptables curl resolvconf 2>&1 | tee /tmp/apt-install.log; then
        debug_log "Package installation successful"
        break
    else
        msg_error "Attempt $attempt failed, retrying..."
        debug_log "Package installation failed, log:"
        tail -10 /tmp/apt-install.log >&2
        sleep 5
        if [ $attempt -eq 3 ]; then
            msg_error "Failed to install required packages after 3 attempts"
            exit 1
        fi
    fi
done
msg_ok "Installed required packages"


msg_info "Installing Tailscale"
debug_log "Starting Tailscale installation"
for attempt in 1 2 3; do
    debug_log "Tailscale installation attempt $attempt"
    debug_log "Downloading Tailscale GPG key..."
    if timeout 60 curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null; then
        debug_log "GPG key downloaded successfully"
    else
        debug_log "GPG key download failed"
        continue
    fi
    
    debug_log "Adding Tailscale repository..."
    if timeout 60 curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list; then
        debug_log "Repository added successfully"
    else
        debug_log "Repository addition failed"
        continue
    fi
    
    debug_log "Updating package lists..."
    if timeout 180 apt update 2>&1 | tee /tmp/apt-update.log; then
        debug_log "Package lists updated successfully"
    else
        debug_log "Package list update failed"
        continue
    fi
    
    debug_log "Installing Tailscale package..."
    if timeout 300 apt install -y tailscale 2>&1 | tee /tmp/tailscale-install.log; then
        debug_log "Tailscale package installed successfully"
    else
        debug_log "Tailscale package installation failed"
        continue
    fi
    
    debug_log "Enabling Tailscale service..."
    if systemctl enable tailscaled; then
        debug_log "Tailscale service enabled successfully"
        break
    else
        debug_log "Tailscale service enable failed"
        continue
    fi
    
    if [ $attempt -eq 3 ]; then
        msg_error "Failed to install Tailscale after 3 attempts"
        debug_log "Final attempt failed, showing logs:"
        [ -f /tmp/apt-update.log ] && tail -10 /tmp/apt-update.log >&2
        [ -f /tmp/tailscale-install.log ] && tail -10 /tmp/tailscale-install.log >&2
        exit 1
    fi
    
    msg_error "Tailscale installation attempt $attempt failed, retrying..."
    sleep 5
done
msg_ok "Installed Tailscale"


msg_info "Installing iptables-persistent"
for attempt in 1 2 3; do
    if timeout 300 bash -c "DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent"; then
        break
    else
        msg_error "iptables-persistent installation attempt $attempt failed, retrying..."
        sleep 5
        if [ $attempt -eq 3 ]; then
            msg_error "Failed to install iptables-persistent after 3 attempts"
            exit 1
        fi
    fi
done
msg_ok "Installed iptables-persistent"


msg_info "Creating Mullvad + Tailscale setup script"
debug_log "Creating setup script at /root/mullvad-tailscale-setup.sh"
cat > /root/mullvad-tailscale-setup.sh << 'EOFSCRIPT'
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Mullvad + Tailscale Exit Node Setup ===${NC}\n"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

if [ ! -c /dev/net/tun ]; then
    echo -e "${RED}ERROR: /dev/net/tun not found!${NC}"
    echo "Please add these lines to your LXC config on Proxmox host:"
    echo "  lxc.cgroup2.devices.allow: c 10:200 rwm"
    echo "  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
    echo "  lxc.cap.drop:"
    exit 1
fi

echo -e "${GREEN}✓ TUN device found${NC}"

echo -e "\n${YELLOW}Updating system...${NC}"
apt update && apt upgrade -y

echo -e "\n${YELLOW}=== Mullvad Configuration ===${NC}"
echo "Please paste your Mullvad WireGuard configuration below."
echo "Get it from: https://mullvad.net/en/account/#/wireguard-config/"
echo -e "${YELLOW}Paste the entire config and press Ctrl+D when done:${NC}\n"

mkdir -p /etc/wireguard
cat > /etc/wireguard/mullvad.conf
chmod 600 /etc/wireguard/mullvad.conf

echo -e "\n${GREEN}✓ Mullvad config saved${NC}"

echo -e "\n${YELLOW}Configuring DNS...${NC}"
sed -i 's/^DNS = .*/DNS = 1.1.1.1, 8.8.8.8/' /etc/wireguard/mullvad.conf

echo -e "\n${YELLOW}Testing Mullvad connection...${NC}"
wg-quick up mullvad

sleep 3

if wg show | grep -q "interface: mullvad"; then
    echo -e "${GREEN}✓ Mullvad connected successfully${NC}"
    
  
    if curl -s --max-time 10 https://am.i.mullvad.net/connected | grep -q "You are connected"; then
        echo -e "${GREEN}✓ Mullvad connection verified${NC}"
    else
        echo -e "${YELLOW}⚠ Could not verify Mullvad connection, but WireGuard is up${NC}"
    fi
else
    echo -e "${RED}✗ Mullvad connection failed${NC}"
    wg-quick down mullvad
    exit 1
fi

echo -e "\n${YELLOW}Enabling Mullvad on boot...${NC}"
systemctl enable wg-quick@mullvad

echo -e "\n${YELLOW}Starting Tailscale...${NC}"
systemctl enable --now tailscaled

echo -e "\n${YELLOW}=== Tailscale Authentication ===${NC}"
echo "Starting Tailscale as exit node..."
echo "Please authenticate via the URL that will appear below:"
tailscale up --advertise-exit-node --accept-routes --accept-dns=false

echo -e "\n${YELLOW}Waiting for Tailscale to connect...${NC}"
sleep 5

if tailscale status | grep -q "100."; then
    echo -e "${GREEN}✓ Tailscale connected${NC}"
else
    echo -e "${RED}✗ Tailscale connection failed${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf

echo -e "${GREEN}✓ IP forwarding enabled${NC}"

echo -e "\n${YELLOW}Creating VPN routing script...${NC}"
cat > /usr/local/bin/setup-vpn-routing.sh << 'EOFROUTINGSCRIPT'
#!/bin/bash

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

ip rule add from all to 100.100.100.100/32 lookup main priority 9000 2>/dev/null || true
ip rule add from all to 3.0.0.0/8 lookup main priority 9000 2>/dev/null || true

iptables -t nat -F POSTROUTING
iptables -F FORWARD

iptables -A FORWARD -i tailscale0 -o mullvad -j ACCEPT
iptables -A FORWARD -i mullvad -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -t nat -A POSTROUTING -o mullvad -j MASQUERADE

iptables -t nat -I POSTROUTING -d 100.64.0.0/10 -j ACCEPT

mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "VPN routing configured successfully"
EOFROUTINGSCRIPT

chmod +x /usr/local/bin/setup-vpn-routing.sh

echo -e "\n${YELLOW}Setting up routing rules...${NC}"
/usr/local/bin/setup-vpn-routing.sh

echo -e "\n${YELLOW}Creating systemd service for automatic routing...${NC}"
cat > /etc/systemd/system/vpn-routing.service << 'EOFSERVICE'
[Unit]
Description=VPN Routing Setup
After=wg-quick@mullvad.service tailscaled.service
Wants=wg-quick@mullvad.service tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-vpn-routing.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload
systemctl enable vpn-routing.service
systemctl start vpn-routing.service

echo -e "${GREEN}✓ VPN routing service created and enabled${NC}"

echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"

echo "Checking services status..."
echo -e "\n${YELLOW}Mullvad:${NC}"
systemctl status wg-quick@mullvad --no-pager | grep "Active:"

echo -e "\n${YELLOW}Tailscale:${NC}"
systemctl status tailscaled --no-pager | grep "Active:"

echo -e "\n${YELLOW}VPN Routing:${NC}"
systemctl status vpn-routing.service --no-pager | grep "Active:"

echo -e "\n${YELLOW}Current IP:${NC}"
curl -s https://ipinfo.io/ip

echo -e "\n${YELLOW}Mullvad Status:${NC}"
curl -s https://am.i.mullvad.net/connected

echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find your container in the machines list"
echo "3. Click the three dots (⋮) menu"
echo "4. Select 'Edit route settings'"
echo "5. Enable 'Use as exit node'"
echo ""
echo "Then on your devices:"
echo "  tailscale up --exit-node=<this-container-name>"
echo ""
echo -e "${GREEN}✓ All done! Your Mullvad exit node is ready!${NC}"
EOFSCRIPT

chmod +x /root/mullvad-tailscale-setup.sh
debug_log "Setup script created and made executable"
msg_ok "Created Mullvad + Tailscale setup script"

debug_log "Running motd_ssh"
motd_ssh
debug_log "Running customize"
customize

msg_info "Cleaning up"
debug_log "Starting cleanup process"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
debug_log "Cleanup completed"
msg_ok "Cleaned"
debug_log "Installation script completed successfully"
