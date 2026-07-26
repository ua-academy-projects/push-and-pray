#!/usr/bin/env bash
set -Eeuo pipefail

readonly PASSWORD_FILE="/tmp/aegis-mariadb-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/history.env"
readonly SERVICE_FILE="/etc/systemd/system/aegis-history.service"
readonly SERVICE_DIRECTORY="/opt/aegis/history-service"
readonly VENV_DIRECTORY="${SERVICE_DIRECTORY}/.venv"
readonly HISTORY_ADDRESS="192.168.100.11"
readonly HISTORY_PORT="8002"
readonly PROVIDER_URL="http://192.168.100.12:8001"
readonly DATABASE_ADDRESS="192.168.100.13"
readonly DATABASE_PORT="3306"

fail() {
  echo "Aegis History provisioning failed: $*" >&2
  exit 1
}

[[ -f "${PASSWORD_FILE}" ]] || \
  fail "missing MariaDB password upload; check AEGIS_DATABASE_SECRET_FILE"
trap 'rm -f "${PASSWORD_FILE}"' EXIT
[[ -x "${VENV_DIRECTORY}/bin/uvicorn" ]] || \
  fail "History virtual environment is not installed"
[[ -x "${VENV_DIRECTORY}/bin/alembic" ]] || fail "Alembic is not installed"
[[ -f "${SERVICE_DIRECTORY}/alembic.ini" ]] || fail "alembic.ini is not installed"
[[ -d "${SERVICE_DIRECTORY}/alembic" ]] || fail "migration files are not installed"

MARIADB_PASSWORD="$(<"${PASSWORD_FILE}")"
[[ -n "${MARIADB_PASSWORD}" ]] || fail "MariaDB password must not be empty"
[[ "${MARIADB_PASSWORD}" != *$'\n'* ]] || \
  fail "MariaDB password file must contain exactly one line"
[[ "${MARIADB_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "MariaDB password contains unsupported characters"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"
temporary_environment="$(mktemp)"
temporary_service="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${temporary_service}" "${PASSWORD_FILE}"' EXIT

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
} >"${temporary_environment}"
install -o root -g aegis -m 0640 "${temporary_environment}" "${ENVIRONMENT_FILE}"

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
    if "${VENV_DIRECTORY}/bin/python" - "${DATABASE_ADDRESS}" "${DATABASE_PORT}" <<'PY'
import socket
import sys

with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=2):
    pass
PY
    then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  fail "MariaDB did not accept TCP connections"
}

wait_for_database
# Provider readiness is local and does not call AbuseIPDB or consume quota.
wait_for_url "${PROVIDER_URL}/health/ready" "Provider Service readiness"

unset ABUSEIPDB_API_KEY
set -a
# Values are generated above and constrained to safe EnvironmentFile syntax.
# shellcheck disable=SC1090
source "${ENVIRONMENT_FILE}"
set +a

systemctl stop aegis-history.service 2>/dev/null || true
if ! (
  cd "${SERVICE_DIRECTORY}"
  runuser --preserve-environment -u aegis -- \
    "${VENV_DIRECTORY}/bin/alembic" -c alembic.ini upgrade head
); then
  fail "Alembic migration failed"
fi

cat >"${temporary_service}" <<EOF
[Unit]
Description=Aegis History Service
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
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict

[Install]
WantedBy=multi-user.target
EOF
install -o root -g root -m 0644 "${temporary_service}" "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable --now aegis-history.service
systemctl restart aegis-history.service

wait_for_url "http://${HISTORY_ADDRESS}:${HISTORY_PORT}/health/live" \
  "History Service liveness"
wait_for_url "http://${HISTORY_ADDRESS}:${HISTORY_PORT}/health/ready" \
  "History Service readiness and MariaDB connectivity"

echo "History Service is healthy at http://${HISTORY_ADDRESS}:${HISTORY_PORT}"
echo "Provider readiness and MariaDB connectivity verified"
