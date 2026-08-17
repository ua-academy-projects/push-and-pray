#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

sync_docker_project
write_compose_env

disable_native_units oil-history.service

docker_compose history up --detach --build --remove-orphans
wait_for_compose_health history history 120

allow_port_if_firewall_active 8001

log "History Compose project is ready: API ${HISTORY_LAN_IP}:8001"
