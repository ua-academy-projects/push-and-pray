#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

configure_common_system

if systemctl is-active --quiet weather-ui.service 2>/dev/null; then
    log "Stopping native host systemd service weather-ui.service"
    systemctl disable --now weather-ui.service || true
    rm -f /etc/systemd/system/weather-ui.service
fi

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing UI port through firewall"
    ufw allow 5000/tcp || true
fi

log "Launching UI Service container via Docker Compose"
cd /vagrant/ui-service
docker compose up -d --build

log "UI Service VM provisioning completed"
