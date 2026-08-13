#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

sync_docker_project
write_compose_env

if systemctl is-active --quiet rabbitmq-server 2>/dev/null && command -v rabbitmqctl >/dev/null 2>&1; then
  queued_messages="$(rabbitmqctl -q list_queues -p oil_tracker messages_ready 2>/dev/null \
    | awk 'NR > 1 { total += $1 } END { print total + 0 }')"
  if [[ "${queued_messages}" -gt 0 ]]; then
    log "Native RabbitMQ still has ${queued_messages} queued messages; wait for History to consume them before container migration"
    exit 1
  fi
fi

disable_native_units oil-history.service rabbitmq-server.service

docker_compose history up --detach rabbitmq
wait_for_compose_health history rabbitmq 90

if ! docker_compose history exec -T rabbitmq \
  rabbitmqctl -q list_vhosts | grep -Fxq oil_tracker; then
  docker_compose history exec -T rabbitmq \
    rabbitmqctl add_vhost oil_tracker
fi

if docker_compose history exec -T rabbitmq \
  rabbitmqctl -q list_users | awk '{print $1}' | grep -Fxq "${RABBITMQ_USER}"; then
  docker_compose history exec -T rabbitmq \
    rabbitmqctl change_password "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
else
  docker_compose history exec -T rabbitmq \
    rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
fi

docker_compose history exec -T rabbitmq \
  rabbitmqctl set_user_tags "${RABBITMQ_USER}" management
docker_compose history exec -T rabbitmq \
  rabbitmqctl set_permissions -p oil_tracker "${RABBITMQ_USER}" '.*' '.*' '.*'

docker_compose history up --detach --build --remove-orphans history
wait_for_compose_health history history 120

allow_port_if_firewall_active 5672
allow_port_if_firewall_active 15672
allow_port_if_firewall_active 8001

log "History Compose project is ready: API ${HISTORY_LAN_IP}:8001, AMQP :5672, management :15672"
