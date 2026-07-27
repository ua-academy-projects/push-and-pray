#!/usr/bin/env bash
set -euo pipefail

readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/ui.env"
readonly SERVICE_FILE="/etc/systemd/system/aegis-ui.service"
readonly SERVICE_DIRECTORY="/opt/aegis/ui-service"
readonly VENV_DIRECTORY="${SERVICE_DIRECTORY}/.venv"
readonly UI_ADDRESS="192.168.100.10"
readonly UI_PORT="8000"
readonly HISTORY_URL="http://192.168.100.11:8002"
readonly REDIS_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis UI provisioning failed: $*" >&2
  exit 1
}

[[ -x "${VENV_DIRECTORY}/bin/uvicorn" ]] || \
  fail "UI virtual environment is not installed"
[[ -d "${SERVICE_DIRECTORY}/src/ui_service" ]] || \
  fail "UI source is not installed"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"
temporary_environment="$(mktemp)"
temporary_service="$(mktemp)"
trap 'rm -f "${temporary_environment}" "${temporary_service}"' EXIT

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
  printf 'REDIS_USERNAME=\n'
  printf 'REDIS_PASSWORD=\n'
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

wait_for_redis() {
  local attempts=30
  while (( attempts > 0 )); do
    if redis-cli -h "${REDIS_ADDRESS}" -p 6379 ping 2>/dev/null | grep -Fxq PONG; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "Redis did not become ready for initial UI startup"
}

wait_for_redis

cat >"${temporary_service}" <<EOF
[Unit]
Description=Aegis UI Service
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
ExecStart=${VENV_DIRECTORY}/bin/uvicorn ui_service.main:app --app-dir ${SERVICE_DIRECTORY}/src --host 0.0.0.0 --port ${UI_PORT} --no-access-log
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=30s
SyslogIdentifier=aegis-ui
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

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "${SERVICE_FILE}" || fail "systemd unit verification failed"
fi

systemctl daemon-reload
systemctl enable aegis-ui.service
systemctl restart aegis-ui.service

wait_for_health() {
  local path="$1"
  local attempts=30

  while (( attempts > 0 )); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
      "http://${UI_ADDRESS}:${UI_PORT}${path}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  fail "UI health check ${path} did not become ready"
}

wait_for_health "/health/live"
wait_for_health "/health/ready"

echo "UI Service is healthy at http://${UI_ADDRESS}:${UI_PORT}"
