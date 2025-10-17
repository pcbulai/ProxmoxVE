#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/pcbulai/ProxmoxVE/main/misc/build.func)


APP="Mullvad"
var_tags="${var_tags:-vpn;mullvad;tailscale}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/wireguard/mullvad.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP LXC"
  
  msg_info "Updating Tailscale"
  $STD apt install -y tailscale
  msg_ok "Updated Tailscale"
  
  exit
}

start
build_container

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "\n${YW}═══════════════════════════════════════${CL}"
echo -e "${YW}Container Details:${CL}"
echo -e "${YW}═══════════════════════════════════════${CL}"
echo -e "  ${DGN}CT ID:${CL}      ${BL}$CTID${CL}"
echo -e "  ${DGN}Hostname:${CL}   ${BL}$(pct config "$CTID" | grep '^hostname:' | awk '{print $2}')${CL}"
echo -e "  ${DGN}IP:${CL}         ${BL}$(pct exec "$CTID" -- ip -4 addr show eth0 | grep inet | awk '{print $2}' | cut -d/ -f1)${CL}"
echo -e "\n${YW}═══════════════════════════════════════${CL}"
echo -e "${YW}Next Steps:${CL}"
echo -e "${YW}═══════════════════════════════════════${CL}\n"
echo -e "${BOLD}1.${NC} Enter the container:"
echo -e "   ${BL}pct enter $CTID${CL}\n"
echo -e "${BOLD}2.${NC} Run the Mullvad + Tailscale setup:"
echo -e "   ${BL}/root/mullvad-tailscale-setup.sh${CL}"
echo -e "   ${DGN}This will:${CL}"
echo -e "   ${DGN}- Install Mullvad and Tailscale${CL}"
echo -e "   ${DGN}- Prompt for your Mullvad config${CL}" 
echo -e "   ${DGN}- Authenticate Tailscale (browser required)${CL}"
echo -e "   ${DGN}- Configure routing${CL}\n"
echo -e "${BOLD}3.${NC} Enable exit node:"
echo -e "   ${DGN}Go to:${CL} ${BL}https://login.tailscale.com/admin/machines${CL}"
echo -e "   ${DGN}Find your container → Edit route settings → Enable 'Use as exit node'${CL}\n"
echo -e "${BOLD}4.${NC} Use from your devices:"
echo -e "   ${BL}tailscale up --exit-node=$(pct config "$CTID" | grep '^hostname:' | awk '{print $2}')${CL}\n"
