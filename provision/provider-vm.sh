#!/usr/bin/env bash
set -euo pipefail

readonly API_KEY_FILE="/tmp/aegis-provider-api-key"
readonly RABBITMQ_PASSWORD_FILE="/tmp/aegis-rabbitmq-provider-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/provider.env"
readonly SERVICE_FILE="/etc/systemd/system/aegis-provider-api.service"
readonly LEGACY_SERVICE_FILE="/etc/systemd/system/aegis-provider.service"
readonly WORKER_SERVICE_FILE="/etc/systemd/system/aegis-provider-blacklist-worker.service"
readonly SERVICE_DIRECTORY="/opt/aegis/provider-service"
readonly VENV_DIRECTORY="${SERVICE_DIRECTORY}/.venv"
readonly PROVIDER_ADDRESS="192.168.100.12"
readonly PROVIDER_PORT="8001"
readonly OUTBOX_DIRECTORY="/var/lib/aegis-provider"
readonly RABBITMQ_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis Provider provisioning failed: $*" >&2
  exit 1
}

[[ -f "${API_KEY_FILE}" ]] || \
  fail "missing Provider API-key upload; check AEGIS_PROVIDER_SECRET_FILE"
[[ -f "${RABBITMQ_PASSWORD_FILE}" ]] || \
  fail "missing RabbitMQ password upload; check AEGIS_RABBITMQ_PROVIDER_SECRET_FILE"
trap 'rm -f "${API_KEY_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT
[[ -x "${VENV_DIRECTORY}/bin/uvicorn" ]] || \
  fail "Provider virtual environment is not installed"
[[ -x "${VENV_DIRECTORY}/bin/aegis-provider-blacklist-worker" ]] || \
  fail "Provider blacklist worker is not installed"
[[ -d "${SERVICE_DIRECTORY}/src/provider_service" ]] || \
  fail "Provider source is not installed"

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
install -d -o aegis -g aegis -m 0750 "${OUTBOX_DIRECTORY}"

temporary_environment="$(mktemp)"
temporary_service="$(mktemp)"
temporary_worker_service="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${temporary_service}" "${temporary_worker_service}" "${API_KEY_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

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
  printf 'BLACKLIST_OUTBOX_PATH=%s/blacklist-outbox.sqlite3\n' "${OUTBOX_DIRECTORY}"
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
} >"${temporary_environment}"

if grep -Eq '^(MARIADB_|DATABASE_URL=|REDIS_)' "${temporary_environment}"; then
  fail "Provider environment contains a database or Redis dependency"
fi

install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

wait_for_rabbitmq() {
  local attempts=30
  while (( attempts > 0 )); do
    if (
      set -a
      # shellcheck disable=SC1090
      source "${ENVIRONMENT_FILE}"
      set +a
      cd "${SERVICE_DIRECTORY}"
      runuser --preserve-environment -u aegis -- \
        "${VENV_DIRECTORY}/bin/python" <<'PY'
import asyncio

from provider_service.config import get_settings
from provider_service.rabbitmq_publisher import AioPikaBlacklistPublisher

async def check() -> None:
    publisher = AioPikaBlacklistPublisher(get_settings())
    await publisher.connect()
    await publisher.close()

asyncio.run(check())
PY
    ) >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "Provider could not authenticate to RabbitMQ or declare its exchange"
}

wait_for_rabbitmq

cat >"${temporary_service}" <<EOF
[Unit]
Description=Aegis Provider API
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60s
StartLimitBurst=5

[Service]
Type=simple
User=aegis
Group=aegis
WorkingDirectory=${SERVICE_DIRECTORY}
EnvironmentFile=${ENVIRONMENT_FILE}
ExecStart=${VENV_DIRECTORY}/bin/uvicorn provider_service.main:app --app-dir ${SERVICE_DIRECTORY}/src --host ${PROVIDER_ADDRESS} --port ${PROVIDER_PORT} --no-access-log
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=30s
SyslogIdentifier=aegis-provider-api
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict

[Install]
WantedBy=multi-user.target
EOF
install -o root -g root -m 0644 "${temporary_service}" "${SERVICE_FILE}"

cat >"${temporary_worker_service}" <<EOF
[Unit]
Description=Aegis Provider Blacklist Polling Worker
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60s
StartLimitBurst=5

[Service]
Type=simple
User=aegis
Group=aegis
UMask=0027
WorkingDirectory=${SERVICE_DIRECTORY}
EnvironmentFile=${ENVIRONMENT_FILE}
ExecStart=${VENV_DIRECTORY}/bin/aegis-provider-blacklist-worker
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=45s
SyslogIdentifier=aegis-provider-blacklist-worker
StandardOutput=journal
StandardError=journal
StateDirectory=aegis-provider
StateDirectoryMode=0750
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=${OUTBOX_DIRECTORY}

[Install]
WantedBy=multi-user.target
EOF
install -o root -g root -m 0644 \
  "${temporary_worker_service}" "${WORKER_SERVICE_FILE}"

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "${SERVICE_FILE}" "${WORKER_SERVICE_FILE}" || \
    fail "systemd unit verification failed"
fi

systemctl disable --now aegis-provider.service 2>/dev/null || true
rm -f "${LEGACY_SERVICE_FILE}"
systemctl daemon-reload
systemctl enable aegis-provider-api.service
systemctl enable aegis-provider-blacklist-worker.service
systemctl restart aegis-provider-api.service
systemctl restart aegis-provider-blacklist-worker.service

wait_for_health() {
  local path="$1"
  local attempts=30

  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "http://${PROVIDER_ADDRESS}:${PROVIDER_PORT}${path}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  fail "Provider health check ${path} did not become ready"
}

wait_for_health "/health/live"
wait_for_health "/health/ready"

echo "Provider Service is healthy at http://${PROVIDER_ADDRESS}:${PROVIDER_PORT}"
