#!/bin/bash

set -euo pipefail

source /vagrant/infrastructure/vagrant/provisioning/common.sh

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

DATABASE_IP="$(resolve_vm_ipv4 database.local)"
PROVIDER_IP="$(resolve_vm_ipv4 provider-service.local)"

export DATABASE_IP
export PROVIDER_IP

log "Database VM resolved to ${DATABASE_IP}"
log "Provider VM resolved to ${PROVIDER_IP}"

log "Launching Backend Service container via Docker Compose"

docker compose \
    --file /vagrant/infrastructure/compose/backend-service.yml \
    up -d --build

log "Backend Service VM provisioning completed"