#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: doomedramen
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://siloserver.org/ | Github: https://github.com/Silo-Server/silo-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  git \
  libvips-dev \
  fonts-noto-core \
  fonts-noto-cjk \
  redis-server
msg_ok "Installed Dependencies"

setup_deb822_repo \
  "jellyfin" \
  "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
  "https://repo.jellyfin.org/debian" \
  "$(get_os_info codename)"

msg_info "Installing Jellyfin FFmpeg"
$STD apt install -y jellyfin-ffmpeg8
ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe
msg_ok "Installed Jellyfin FFmpeg"

setup_hwaccel

PG_VERSION="18" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="silo" PG_DB_USER="silo" PG_DB_EXTENSIONS="vector,pg_trgm,citext,pg_stat_statements" setup_postgresql_db

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
  -o /usr/local/bin/silo ./cmd/silo/
msg_ok "Built Silo"

msg_info "Configuring Silo"
mkdir -p /etc/silo /var/lib/silo/{artwork,plugins,compat/jellyfin-web,transcode,download-artifacts}
cat <<EOF >/etc/silo/silo.env
SECRET_KEY=$(random_password 64)
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}?sslmode=disable
REDIS_URL=redis://127.0.0.1:6379
PORT=8080
JF_PORT=8096
ABS_PORT=13378
SILO_PLUGIN_CACHE_DIR=/var/lib/silo/plugins
SILO_TRANSCODE_DIR=/var/lib/silo/transcode
SILO_DOWNLOAD_ARTIFACT_DIR=/var/lib/silo/download-artifacts
NODE_OPTIONS=--use-openssl-ca
EOF
chmod 600 /etc/silo/silo.env
msg_ok "Configured Silo"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/silo.service
[Unit]
Description=Silo Media Server
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/silo
EnvironmentFile=/etc/silo/silo.env
ExecStart=/usr/local/bin/silo
Restart=on-failure
RestartSec=5
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now silo
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
