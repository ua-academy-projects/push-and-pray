#!/usr/bin/env bash

set -euo pipefail

source /vagrant/infrastructure/vagrant/provisioning/common.sh

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

BACKEND_IP="$(resolve_vm_ipv4 backend-service.local)"
DATABASE_IP="$(resolve_vm_ipv4 database.local)"

export BACKEND_IP
export DATABASE_IP

log "Backend VM resolved to ${BACKEND_IP}"
log "Database VM resolved to ${DATABASE_IP}"

log "Launching UI Service container via Docker Compose"

docker compose \
    --file /vagrant/infrastructure/compose/ui-service.yml \
    up -d --build

log "UI Service VM provisioning completed"