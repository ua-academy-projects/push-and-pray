#!/usr/bin/env bash

set -euo pipefail

source /vagrant/infrastructure/vagrant/provisioning/common.sh

configure_common_system

for service in weather-provider.service weather-history.service; do
    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        log "Stopping native host systemd service ${service}"
        systemctl disable --now "${service}" || true
        rm -f "/etc/systemd/system/${service}"
    fi
done

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing Provider port through firewall"
    ufw allow 5002/tcp || true
fi

log "Launching Provider Service container via Docker Compose"
docker compose \
    --file /vagrant/infrastructure/compose/provider-service.yml \
    up -d --build

log "Provider Service VM provisioning completed"
