#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: doomedramen
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://siloserver.org/ | Github: https://github.com/Silo-Server/silo-server

APP="Silo"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-24}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/silo ]]; then
    msg_error "No Silo Installation Found!"
    exit
  fi

  if check_for_gh_branch "silo" "Silo-Server/silo-server" "main"; then
    fetch_and_deploy_gh_branch "silo" "Silo-Server/silo-server" "main"

    GO_VERSION="$(sed -n 's/^go //p' /opt/silo/go.mod)" setup_go
    NODE_VERSION="24" NODE_MODULE="pnpm@$(jq -r '.packageManager | split("@")[1]' /opt/silo/web/package.json)" setup_nodejs

    msg_info "Building Silo"
    cd /opt/silo/web
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    cd /opt/silo
    $STD go build \
      -ldflags "-X github.com/Silo-Server/silo-server/internal/buildinfo.revisionOverride=$(cat ~/.silo) -X github.com/Silo-Server/silo-server/internal/buildinfo.builtAtOverride=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      -o /opt/silo/silo ./cmd/silo/
    msg_ok "Built Silo"

    msg_info "Stopping Silo"
    systemctl stop silo
    msg_ok "Stopped Silo"

    msg_info "Updating Silo"
    $STD apt update
    $STD apt -y --with-new-pkgs upgrade jellyfin-ffmpeg8 libvips-dev postgresql-client-18
    install -m 0755 /opt/silo/silo /usr/local/bin/silo
    msg_ok "Updated Silo"

    msg_info "Starting Silo"
    systemctl start silo
    msg_ok "Started Silo"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
