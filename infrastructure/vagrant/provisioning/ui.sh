#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

sync_docker_project
write_compose_env

disable_native_units oil-ui.service redis-server.service

docker_compose ui up --detach --build --remove-orphans
wait_for_compose_health ui redis 90
wait_for_compose_health ui ui 150

allow_port_if_firewall_active 6379
allow_port_if_firewall_active 8080

log "UI Compose project is ready: application ${UI_LAN_IP}:8080, Redis :6379"
