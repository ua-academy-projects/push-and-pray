#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

configure_common_system

if systemctl is-active --quiet weather-backend.service 2>/dev/null; then
    log "Stopping native host systemd service weather-backend.service"
    systemctl disable --now weather-backend.service || true
    rm -f /etc/systemd/system/weather-backend.service
fi

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing Backend port through firewall"
    ufw allow 5001/tcp || true
fi

log "Launching Backend Service container via Docker Compose"
cd /vagrant/backend-service
docker compose up -d --build

log "Backend Service VM provisioning completed"
