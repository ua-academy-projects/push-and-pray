#!/usr/bin/env bash

set -Eeuo pipefail
set +x

# shellcheck disable=SC1091
source /etc/oilscope/role.conf

export DOCKER_CONFIG=/run/oilscope/docker
RUNTIME_ENV=/opt/oilscope/runtime/.env

cleanup() {
  rm -rf "${DOCKER_CONFIG}"
}
trap cleanup EXIT

install -d -o root -g root -m 0700 "${DOCKER_CONFIG}"
/usr/local/sbin/oilscope-runtime-env

/usr/bin/docker compose \
  --env-file "${RUNTIME_ENV}" \
  --file "${COMPOSE_FILE}" \
  pull

/usr/bin/docker compose \
  --env-file "${RUNTIME_ENV}" \
  --file "${COMPOSE_FILE}" \
  up --detach --no-build --remove-orphans
