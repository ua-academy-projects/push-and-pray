#!/usr/bin/env bash
set -euo pipefail

readonly PASSWORD_FILE="/tmp/aegis-mariadb-password"
readonly RABBITMQ_PASSWORD_FILE="/tmp/aegis-rabbitmq-history-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/history.env"
readonly COMPOSE_FILE="/vagrant/deploy/history-vm/compose.yaml"
readonly HISTORY_ADDRESS="192.168.100.11"
readonly HISTORY_PORT="8002"
readonly PROVIDER_URL="http://192.168.100.12:8001"
readonly DATABASE_ADDRESS="192.168.100.14"
readonly DATABASE_PORT="3306"
readonly RABBITMQ_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis History provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis History: $*"
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

[[ -f "${PASSWORD_FILE}" ]] || \
  fail "missing MariaDB password upload; check AEGIS_DATABASE_SECRET_FILE"
[[ -f "${RABBITMQ_PASSWORD_FILE}" ]] || \
  fail "missing RabbitMQ password upload; check AEGIS_RABBITMQ_HISTORY_SECRET_FILE"
[[ -f "${COMPOSE_FILE}" ]] || fail "missing History Compose definition"
command -v docker >/dev/null || fail "Docker is unavailable"
trap 'rm -f "${PASSWORD_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

MARIADB_PASSWORD="$(<"${PASSWORD_FILE}")"
RABBITMQ_PASSWORD="$(<"${RABBITMQ_PASSWORD_FILE}")"
[[ -n "${MARIADB_PASSWORD}" ]] || fail "MariaDB password must not be empty"
[[ "${MARIADB_PASSWORD}" != *$'\n'* ]] || \
  fail "MariaDB password file must contain exactly one line"
[[ "${MARIADB_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "MariaDB password contains unsupported characters"
[[ -n "${RABBITMQ_PASSWORD}" ]] || fail "RabbitMQ password must not be empty"
[[ "${RABBITMQ_PASSWORD}" != *$'\n'* ]] || \
  fail "RabbitMQ password file must contain exactly one line"
[[ "${RABBITMQ_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "RabbitMQ password contains unsupported characters"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"
temporary_environment="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${PASSWORD_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

{
  printf 'MARIADB_HOST=%s\n' "${DATABASE_ADDRESS}"
  printf 'MARIADB_PORT=%s\n' "${DATABASE_PORT}"
  printf 'MARIADB_DATABASE=aegis_history\n'
  printf 'MARIADB_USER=aegis_history\n'
  printf 'MARIADB_PASSWORD=%s\n' "${MARIADB_PASSWORD}"
  printf 'PROVIDER_SERVICE_URL=%s\n' "${PROVIDER_URL}"
  printf 'PROVIDER_CONNECT_TIMEOUT_SECONDS=5\n'
  printf 'PROVIDER_READ_TIMEOUT_SECONDS=10\n'
  printf 'PROVIDER_WRITE_TIMEOUT_SECONDS=5\n'
  printf 'PROVIDER_POOL_TIMEOUT_SECONDS=5\n'
  printf 'BLACKLIST_STALE_AFTER_SECONDS=43200\n'
  printf 'RABBITMQ_HOST=%s\n' "${RABBITMQ_ADDRESS}"
  printf 'RABBITMQ_PORT=5672\n'
  printf 'RABBITMQ_VIRTUAL_HOST=/aegis\n'
  printf 'RABBITMQ_USERNAME=aegis_history\n'
  printf 'RABBITMQ_PASSWORD=%s\n' "${RABBITMQ_PASSWORD}"
  printf 'RABBITMQ_EXCHANGE_NAME=aegis.blacklist\n'
  printf 'RABBITMQ_QUEUE_NAME=aegis.history.blacklist.snapshots\n'
  printf 'RABBITMQ_RETRY_EXCHANGE_NAME=aegis.blacklist.retry\n'
  printf 'RABBITMQ_DEAD_LETTER_EXCHANGE_NAME=aegis.blacklist.dead\n'
  printf 'RABBITMQ_DEAD_LETTER_QUEUE_NAME=aegis.history.blacklist.snapshots.dead\n'
  printf 'RABBITMQ_ROUTING_KEY=blacklist.snapshot.complete\n'
  printf 'RABBITMQ_PREFETCH_COUNT=1\n'
  printf 'RABBITMQ_CONNECTION_TIMEOUT_SECONDS=10\n'
  printf 'RABBITMQ_PUBLISH_TIMEOUT_SECONDS=10\n'
  printf 'RABBITMQ_SHUTDOWN_TIMEOUT_SECONDS=30\n'
} >"${temporary_environment}"

if grep -Eq '^(ABUSEIPDB_API_KEY=|REDIS_)' "${temporary_environment}"; then
  fail "History environment contains a credential owned by another service"
fi
install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

for unit in \
  aegis-history.service \
  aegis-history-api.service \
  aegis-history-blacklist-consumer.service; do
  systemctl disable --now "${unit}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${unit}"
done
systemctl daemon-reload

export AEGIS_HISTORY_ENV_FILE="${ENVIRONMENT_FILE}"
wait_for_tcp "${DATABASE_ADDRESS}" "${DATABASE_PORT}" MariaDB
wait_for_tcp "${RABBITMQ_ADDRESS}" 5672 RabbitMQ
progress "building History image"
docker compose -f "${COMPOSE_FILE}" config --quiet
docker compose -f "${COMPOSE_FILE}" build
progress "running MariaDB migrations"
docker compose -f "${COMPOSE_FILE}" run --rm --no-deps \
  history-api alembic -c /app/alembic.ini upgrade head
docker compose -f "${COMPOSE_FILE}" run --rm --no-deps \
  history-api alembic -c /app/alembic.ini current --check-heads
progress "starting History API and Consumer containers"
docker compose -f "${COMPOSE_FILE}" up --detach --remove-orphans

wait_for_api() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "http://${HISTORY_ADDRESS}:${HISTORY_PORT}/health/ready" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "History API container did not become ready"
}

wait_for_container_health() {
  local container="$1"
  local attempts=60
  while (( attempts > 0 )); do
    if docker inspect --format '{{.State.Health.Status}}' "${container}" \
      2>/dev/null | grep -Fxq healthy; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "${container} did not become healthy"
}

wait_for_api
wait_for_container_health aegis-history-api
wait_for_container_health aegis-history-consumer

progress "API and Consumer containers are healthy at Alembic head"
