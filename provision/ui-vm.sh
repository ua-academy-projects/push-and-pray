#!/usr/bin/env bash
set -euo pipefail

readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/ui.env"
readonly COMPOSE_FILE="/vagrant/deploy/ui-vm/compose.yaml"
readonly UI_ADDRESS="192.168.100.10"
readonly UI_PORT="8000"
readonly HISTORY_URL="http://192.168.100.11:8002"
readonly REDIS_ADDRESS="192.168.100.14"
readonly REDIS_PASSWORD_FILE="/tmp/aegis-redis-password"

fail() {
  echo "Aegis UI provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis UI: $*"
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local dependency="$3"
  local attempts=90
  progress "waiting for ${dependency} at ${host}:${port}"
  until timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; do
    attempts=$((attempts - 1))
    (( attempts > 0 )) || fail "${dependency} did not become reachable"
    sleep 2
  done
}

[[ -f "${COMPOSE_FILE}" ]] || fail "missing UI Compose definition"
[[ -f "${REDIS_PASSWORD_FILE}" ]] || \
  fail "missing Redis password upload; check AEGIS_REDIS_SECRET_FILE"
command -v docker >/dev/null || fail "Docker is unavailable"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"
temporary_environment="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${REDIS_PASSWORD_FILE}"' EXIT

REDIS_PASSWORD="$(<"${REDIS_PASSWORD_FILE}")"
[[ -n "${REDIS_PASSWORD}" ]] || fail "Redis password must not be empty"
[[ "${REDIS_PASSWORD}" != *$'\n'* ]] || \
  fail "Redis password file must contain exactly one line"
[[ "${REDIS_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "Redis password contains unsupported characters"

{
  printf 'HISTORY_SERVICE_URL=%s\n' "${HISTORY_URL}"
  printf 'HISTORY_CONNECT_TIMEOUT_SECONDS=3\n'
  printf 'HISTORY_READ_TIMEOUT_SECONDS=5\n'
  printf 'HISTORY_WRITE_TIMEOUT_SECONDS=5\n'
  printf 'HISTORY_POOL_TIMEOUT_SECONDS=3\n'
  printf 'HISTORY_OPERATION_TIMEOUT_SECONDS=10\n'
  printf 'REDIS_HOST=%s\n' "${REDIS_ADDRESS}"
  printf 'REDIS_PORT=6379\n'
  printf 'REDIS_DB=0\n'
  printf 'REDIS_USERNAME=aegis_ui\n'
  printf 'REDIS_PASSWORD=%s\n' "${REDIS_PASSWORD}"
  printf 'REDIS_CONNECTION_TIMEOUT_SECONDS=3\n'
  printf 'REDIS_THEME_PREFIX=theme\n'
  printf 'REDIS_THEME_TTL_SECONDS=2592000\n'
  printf 'UI_SESSION_COOKIE_NAME=theme_session\n'
  printf 'UI_SESSION_COOKIE_SECURE=false\n'
} >"${temporary_environment}"

if grep -Eq '^(MARIADB_|DATABASE_URL=|ABUSEIPDB_API_KEY=|RABBITMQ_)' \
  "${temporary_environment}"; then
  fail "UI environment contains a credential owned by another service"
fi
install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

systemctl disable --now aegis-ui.service 2>/dev/null || true
rm -f /etc/systemd/system/aegis-ui.service
systemctl daemon-reload

export AEGIS_UI_ENV_FILE="${ENVIRONMENT_FILE}"
wait_for_tcp 192.168.100.11 8002 "History API"
wait_for_tcp "${REDIS_ADDRESS}" 6379 Redis
progress "building and starting UI container"
docker compose -f "${COMPOSE_FILE}" config --quiet
docker compose -f "${COMPOSE_FILE}" up \
  --detach --build --remove-orphans

wait_for_health() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "http://${UI_ADDRESS}:${UI_PORT}/health/ready" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "UI container did not become ready"
}

wait_for_health
docker inspect --format '{{.State.Health.Status}}' aegis-ui | grep -Fxq healthy || \
  fail "UI container health check is not healthy"

progress "container is healthy at http://${UI_ADDRESS}:${UI_PORT}"
