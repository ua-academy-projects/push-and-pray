#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

for entry in \
  "ui:/vagrant/infra/docker/ui/compose.yml" \
  "api-fetcher:/vagrant/infra/docker/api-fetcher/compose.yml" \
  "backend-service:/vagrant/infra/docker/backend-service/compose.yml" \
  "rabbitmq:/vagrant/infra/docker/rabbitmq/compose.yml" \
  "database:/vagrant/infra/docker/database/compose.yml"; do
  machine="${entry%%:*}"
  compose_file="${entry#*:}"
  vagrant ssh "${machine}" -c "sudo docker compose -f ${compose_file} down"
done

echo "Containers stopped without deleting PostgreSQL or messaging volumes."
