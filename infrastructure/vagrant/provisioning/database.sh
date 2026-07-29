#!/usr/bin/env bash

set -euo pipefail

source /vagrant/infrastructure/vagrant/provisioning/common.sh

configure_common_system

log "Stopping and disabling any native host services (PostgreSQL, Redis, RabbitMQ)"
for service in postgresql redis-server rabbitmq-server; do
    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        systemctl disable --now "${service}" || true
    fi
done

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing Database, Redis, and RabbitMQ ports through firewall"
    ufw allow 5432/tcp || true
    ufw allow 6379/tcp || true
    ufw allow 5672/tcp || true
    ufw allow 15672/tcp || true
fi

log "Launching Database containers (PostgreSQL, Redis, RabbitMQ) via Docker Compose"
docker compose \
    --file /vagrant/infrastructure/compose/database-service.yml \
    up -d --build

log "Database VM provisioning completed"
