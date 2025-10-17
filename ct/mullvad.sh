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
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP LXC"
  
  exit
}

start
build_container

description

msg_ok "Completed Successfully!\n"
