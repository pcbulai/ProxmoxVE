#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"

$STD apt install -y wireguard-tools iptables curl resolvconf iptables-persistent

msg_info "Installing Tailscale"
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
$STD apt update
$STD apt install -y tailscale
$STD systemctl enable tailscaled
msg_ok "Installed Tailscale"

read -r -p "${TAB3}Ready to paste your Mullvad config? Press Enter to continue..."
msg_info "Paste your Mullvad WireGuard configuration below"
echo "Press Ctrl+D when done:"
cat > /etc/wireguard/mullvad.conf
chmod 600 /etc/wireguard/mullvad.conf

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"
