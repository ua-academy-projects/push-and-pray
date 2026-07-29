#!/usr/bin/env bash
set -euo pipefail

readonly API_KEY_FILE="/tmp/aegis-provider-api-key"
readonly RABBITMQ_PASSWORD_FILE="/tmp/aegis-rabbitmq-provider-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/provider.env"
readonly COMPOSE_FILE="/vagrant/deploy/provider-vm/compose.yaml"
readonly PROVIDER_ADDRESS="192.168.100.12"
readonly PROVIDER_PORT="8001"
readonly RABBITMQ_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis Provider provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis Provider: $*"
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

[[ -f "${API_KEY_FILE}" ]] || \
  fail "missing Provider API-key upload; check AEGIS_PROVIDER_SECRET_FILE"
[[ -f "${RABBITMQ_PASSWORD_FILE}" ]] || \
  fail "missing RabbitMQ password upload; check AEGIS_RABBITMQ_PROVIDER_SECRET_FILE"
[[ -f "${COMPOSE_FILE}" ]] || fail "missing Provider Compose definition"
command -v docker >/dev/null || fail "Docker is unavailable"
trap 'rm -f "${API_KEY_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

ABUSEIPDB_API_KEY="$(<"${API_KEY_FILE}")"
RABBITMQ_PASSWORD="$(<"${RABBITMQ_PASSWORD_FILE}")"
[[ -n "${ABUSEIPDB_API_KEY}" ]] || fail "AbuseIPDB API key must not be empty"
[[ "${ABUSEIPDB_API_KEY}" != *$'\n'* ]] || \
  fail "API key file must contain exactly one line"
[[ "${ABUSEIPDB_API_KEY}" =~ ^[A-Za-z0-9._-]+$ ]] || \
  fail "API key contains unsupported characters"
[[ -n "${RABBITMQ_PASSWORD}" ]] || fail "RabbitMQ password must not be empty"
[[ "${RABBITMQ_PASSWORD}" != *$'\n'* ]] || \
  fail "RabbitMQ password file must contain exactly one line"
[[ "${RABBITMQ_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "RabbitMQ password contains unsupported characters"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"
temporary_environment="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${API_KEY_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

{
  printf 'ABUSEIPDB_BASE_URL=https://api.abuseipdb.com\n'
  printf 'ABUSEIPDB_API_KEY=%s\n' "${ABUSEIPDB_API_KEY}"
  printf 'ABUSEIPDB_CONNECT_TIMEOUT_SECONDS=5\n'
  printf 'ABUSEIPDB_READ_TIMEOUT_SECONDS=10\n'
  printf 'ABUSEIPDB_WRITE_TIMEOUT_SECONDS=5\n'
  printf 'ABUSEIPDB_POOL_TIMEOUT_SECONDS=5\n'
  printf 'ABUSEIPDB_OPERATION_TIMEOUT_SECONDS=20\n'
  printf 'BLACKLIST_POLLING_ENABLED=true\n'
  printf 'BLACKLIST_POLL_INTERVAL_SECONDS=21600\n'
  printf 'BLACKLIST_CONFIDENCE_MINIMUM=90\n'
  printf 'RABBITMQ_HOST=%s\n' "${RABBITMQ_ADDRESS}"
  printf 'RABBITMQ_PORT=5672\n'
  printf 'RABBITMQ_VIRTUAL_HOST=/aegis\n'
  printf 'RABBITMQ_USERNAME=aegis_provider\n'
  printf 'RABBITMQ_PASSWORD=%s\n' "${RABBITMQ_PASSWORD}"
  printf 'RABBITMQ_EXCHANGE_NAME=aegis.blacklist\n'
  printf 'RABBITMQ_ROUTING_KEY=blacklist.snapshot.complete\n'
  printf 'RABBITMQ_CONNECTION_TIMEOUT_SECONDS=10\n'
  printf 'RABBITMQ_PUBLISH_TIMEOUT_SECONDS=10\n'
  printf 'RABBITMQ_PUBLISH_RETRY_INITIAL_SECONDS=30\n'
  printf 'RABBITMQ_PUBLISH_RETRY_MAXIMUM_SECONDS=900\n'
  printf 'RABBITMQ_PUBLISH_MAX_ATTEMPTS=5\n'
} >"${temporary_environment}"

if grep -Eq '^(MARIADB_|DATABASE_URL=|REDIS_)' "${temporary_environment}"; then
  fail "Provider environment contains a database or Redis dependency"
fi
install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

for unit in \
  aegis-provider.service \
  aegis-provider-api.service \
  aegis-provider-blacklist-worker.service; do
  systemctl disable --now "${unit}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${unit}"
done
systemctl daemon-reload

export AEGIS_PROVIDER_ENV_FILE="${ENVIRONMENT_FILE}"
wait_for_tcp "${RABBITMQ_ADDRESS}" 5672 RabbitMQ
progress "building and starting Provider API and Worker containers"
docker compose -f "${COMPOSE_FILE}" config --quiet
docker compose -f "${COMPOSE_FILE}" up \
  --detach --build --remove-orphans

wait_for_api() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "http://${PROVIDER_ADDRESS}:${PROVIDER_PORT}/health/ready" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "Provider API container did not become ready"
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
wait_for_container_health aegis-provider-api
wait_for_container_health aegis-provider-worker

progress "API and Worker containers are healthy"
