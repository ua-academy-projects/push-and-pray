#!/usr/bin/env bash
set -euo pipefail

readonly PASSWORD_FILE="/tmp/aegis-mariadb-password"
readonly RABBITMQ_PASSWORD_FILE="/tmp/aegis-rabbitmq-history-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/history.env"
readonly SERVICE_FILE="/etc/systemd/system/aegis-history-api.service"
readonly LEGACY_SERVICE_FILE="/etc/systemd/system/aegis-history.service"
readonly CONSUMER_SERVICE_FILE="/etc/systemd/system/aegis-history-blacklist-consumer.service"
readonly SERVICE_DIRECTORY="/opt/aegis/history-service"
readonly VENV_DIRECTORY="${SERVICE_DIRECTORY}/.venv"
readonly HISTORY_ADDRESS="192.168.100.11"
readonly HISTORY_PORT="8002"
readonly PROVIDER_URL="http://192.168.100.12:8001"
readonly DATABASE_ADDRESS="192.168.100.13"
readonly DATABASE_PORT="3306"
readonly RABBITMQ_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis History provisioning failed: $*" >&2
  exit 1
}

[[ -f "${PASSWORD_FILE}" ]] || \
  fail "missing MariaDB password upload; check AEGIS_DATABASE_SECRET_FILE"
[[ -f "${RABBITMQ_PASSWORD_FILE}" ]] || \
  fail "missing RabbitMQ password upload; check AEGIS_RABBITMQ_HISTORY_SECRET_FILE"
trap 'rm -f "${PASSWORD_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT
[[ -x "${VENV_DIRECTORY}/bin/uvicorn" ]] || \
  fail "History virtual environment is not installed"
[[ -x "${VENV_DIRECTORY}/bin/alembic" ]] || fail "Alembic is not installed"
[[ -x "${VENV_DIRECTORY}/bin/aegis-history-blacklist-consumer" ]] || \
  fail "History blacklist consumer is not installed"
[[ -f "${SERVICE_DIRECTORY}/alembic.ini" ]] || fail "alembic.ini is not installed"
[[ -d "${SERVICE_DIRECTORY}/alembic" ]] || fail "migration files are not installed"

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
temporary_service="$(mktemp)"
temporary_consumer_service="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${temporary_service}" "${temporary_consumer_service}" "${PASSWORD_FILE}" "${RABBITMQ_PASSWORD_FILE}"' EXIT

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
} >"${temporary_environment}"
install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

if grep -Eq '^(ABUSEIPDB_API_KEY=|REDIS_)' "${temporary_environment}"; then
  fail "History environment contains a credential owned by another service"
fi

wait_for_url() {
  local url="$1"
  local description="$2"
  local attempts=30

  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "${url}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  fail "${description} did not become ready"
}

wait_for_database() {
  local attempts=30

  while (( attempts > 0 )); do
    if (
      cd "${SERVICE_DIRECTORY}"
      runuser --preserve-environment -u aegis -- \
        "${VENV_DIRECTORY}/bin/python" <<'PY'
from sqlalchemy import create_engine, text

from history_service.config import get_settings

engine = create_engine(get_settings().database_url(), pool_pre_ping=True)
try:
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
finally:
    engine.dispose()
PY
    ) >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  fail "History could not authenticate to MariaDB; verify db-vm and AEGIS_DATABASE_SECRET_FILE"
}

wait_for_rabbitmq() {
  local attempts=30
  while (( attempts > 0 )); do
    if (
      cd "${SERVICE_DIRECTORY}"
      runuser --preserve-environment -u aegis -- \
        "${VENV_DIRECTORY}/bin/python" <<'PY'
import asyncio

import aio_pika
from history_service.config import get_settings

async def check() -> None:
    settings = get_settings()
    connection = await aio_pika.connect_robust(
        host=settings.rabbitmq_host,
        port=settings.rabbitmq_port,
        login=settings.rabbitmq_username,
        password=settings.rabbitmq_password.get_secret_value(),
        virtualhost=settings.rabbitmq_virtual_host,
        timeout=settings.rabbitmq_connection_timeout_seconds,
    )
    await connection.close()

asyncio.run(check())
PY
    ) >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "History could not authenticate to RabbitMQ"
}

unset ABUSEIPDB_API_KEY
set -a
# Values are generated above and constrained to safe EnvironmentFile syntax.
# shellcheck disable=SC1090
source "${ENVIRONMENT_FILE}"
set +a

wait_for_database
wait_for_rabbitmq
# Provider readiness is local and does not call AbuseIPDB or consume quota.
wait_for_url "${PROVIDER_URL}/health/ready" "Provider Service readiness"

systemctl stop aegis-history-api.service 2>/dev/null || true
systemctl stop aegis-history-blacklist-consumer.service 2>/dev/null || true
if ! (
  cd "${SERVICE_DIRECTORY}"
  runuser --preserve-environment -u aegis -- \
    "${VENV_DIRECTORY}/bin/alembic" -c alembic.ini upgrade head
); then
  fail "Alembic migration failed"
fi
if ! (
  cd "${SERVICE_DIRECTORY}"
  runuser --preserve-environment -u aegis -- \
    "${VENV_DIRECTORY}/bin/alembic" -c alembic.ini current --check-heads
); then
  fail "MariaDB schema is not at the current Alembic head"
fi

cat >"${temporary_service}" <<EOF
[Unit]
Description=Aegis History API
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
ExecStart=${VENV_DIRECTORY}/bin/uvicorn history_service.main:app --app-dir ${SERVICE_DIRECTORY}/src --host ${HISTORY_ADDRESS} --port ${HISTORY_PORT} --no-access-log
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=30s
SyslogIdentifier=aegis-history-api
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

cat >"${temporary_consumer_service}" <<EOF
[Unit]
Description=Aegis History Blacklist Consumer
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
ExecStart=${VENV_DIRECTORY}/bin/aegis-history-blacklist-consumer
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=45s
SyslogIdentifier=aegis-history-blacklist-consumer
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict

[Install]
WantedBy=multi-user.target
EOF
install -o root -g root -m 0644 \
  "${temporary_consumer_service}" "${CONSUMER_SERVICE_FILE}"

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "${SERVICE_FILE}" "${CONSUMER_SERVICE_FILE}" || \
    fail "systemd unit verification failed"
fi

systemctl disable --now aegis-history.service 2>/dev/null || true
rm -f "${LEGACY_SERVICE_FILE}"
systemctl daemon-reload
systemctl enable aegis-history-api.service
systemctl enable aegis-history-blacklist-consumer.service
systemctl restart aegis-history-api.service
systemctl restart aegis-history-blacklist-consumer.service

wait_for_url "http://${HISTORY_ADDRESS}:${HISTORY_PORT}/health/live" \
  "History Service liveness"
wait_for_url "http://${HISTORY_ADDRESS}:${HISTORY_PORT}/health/ready" \
  "History Service readiness and MariaDB connectivity"
systemctl is-active --quiet aegis-history-blacklist-consumer.service || \
  fail "History blacklist consumer did not become active"

echo "History Service is healthy at http://${HISTORY_ADDRESS}:${HISTORY_PORT}"
echo "Provider readiness, authenticated MariaDB access, and Alembic head verified"
echo "History blacklist consumer is active with application-declared RabbitMQ topology"
