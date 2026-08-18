#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck disable=SC1091
source /etc/oilscope/role.conf

/usr/bin/docker compose \
  --env-file /opt/oilscope/runtime/.env \
  --file "${COMPOSE_FILE}" \
  stop
