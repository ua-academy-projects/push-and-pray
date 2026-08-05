#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

for entry in \
  "ui:/vagrant/infra/docker/ui/compose.yml" \
  "api-fetcher:/vagrant/infra/docker/api-fetcher/compose.yml" \
  "backend-service:/vagrant/infra/docker/backend-service/compose.yml" \
  "rabbitmq:/vagrant/infra/docker/rabbitmq/compose.yml" \
  "database:/vagrant/infra/docker/database/compose.yml" \
  "logs:/vagrant/infra/docker/logs/compose.yml"; do
  machine="${entry%%:*}"
  compose_file="${entry#*:}"
  extra_env=""
  if [[ "${machine}" == logs ]]; then
    extra_env="--env-file /etc/rateboard/logs.env"
  fi
  vagrant ssh "${machine}" -c \
    "sudo docker compose ${extra_env} --env-file /etc/rateboard/alloy.env -f ${compose_file} down"
done

echo "Containers stopped without deleting PostgreSQL, messaging, Loki, or Grafana data."
