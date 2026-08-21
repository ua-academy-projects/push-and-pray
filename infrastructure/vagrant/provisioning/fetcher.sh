#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

if [[ -z "${OILPRICEAPI_KEY:-}" || "${OILPRICEAPI_KEY}" == "replace-me" ]]; then
  log "OILPRICEAPI_KEY is missing from the current process environment."
  exit 1
fi

sync_docker_project
write_compose_env true

disable_native_units oil-fetcher.service
disable_native_units oil-fetcher.service

docker_compose fetcher up --detach --build --remove-orphans
wait_for_compose_health fetcher fetcher 120

allow_port_if_firewall_active 8002

log "Fetcher Compose project is ready at ${FETCHER_LAN_IP}:8002"
