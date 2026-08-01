#!/bin/bash

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

readonly SERVICE_LOG="/var/log/weather-app/database.log"
touch "${SERVICE_LOG}"
chmod 644 "${SERVICE_LOG}"

log "Launching Database containers via Docker Compose"

docker compose \
    --file /vagrant/infrastructure/compose/database-service.yml \
    up -d --build

timestamp="$(date -u '+%Y-%m-%d %H:%M:%S +0000')"
{
    printf '[%s] [INFO] [database] Database containers launched successfully.\n' "${timestamp}"
    docker compose --file /vagrant/infrastructure/compose/database-service.yml ps
} >> "${SERVICE_LOG}" 2>&1

log "Database VM provisioning completed"