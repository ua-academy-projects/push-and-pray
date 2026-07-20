#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
RUN_DIR="${ROOT_DIR}/.run"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create it first: cp .env.example .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${BACKEND_HOST:?BACKEND_HOST must be set in .env}"
: "${BACKEND_PORT:?BACKEND_PORT must be set in .env}"
: "${HISTORY_HOST:?HISTORY_HOST must be set in .env}"
: "${HISTORY_PORT:?HISTORY_PORT must be set in .env}"
: "${UI_HOST:?UI_HOST must be set in .env}"
: "${UI_PORT:?UI_PORT must be set in .env}"
: "${DATABASE_URL:?DATABASE_URL must be set in .env}"
: "${BACKFILL_YEAR_ON_START:?BACKFILL_YEAR_ON_START must be set in .env}"
: "${POSTGRES_BIN_DIR:?POSTGRES_BIN_DIR must be set in .env}"
: "${SERVICE_CHECK_TIMEOUT_SECONDS:?SERVICE_CHECK_TIMEOUT_SECONDS must be set in .env}"
: "${SERVICE_START_ATTEMPTS:?SERVICE_START_ATTEMPTS must be set in .env}"
: "${SERVICE_START_INTERVAL_SECONDS:?SERVICE_START_INTERVAL_SECONDS must be set in .env}"
: "${SERVICE_STOP_ATTEMPTS:?SERVICE_STOP_ATTEMPTS must be set in .env}"
: "${SERVICE_STOP_INTERVAL_SECONDS:?SERVICE_STOP_INTERVAL_SECONDS must be set in .env}"

if [[ -d "${POSTGRES_BIN_DIR}" ]]; then
  export PATH="${POSTGRES_BIN_DIR}:${PATH}"
fi

for command in python3 go psql pg_isready curl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command is not installed: ${command}" >&2
    exit 1
  fi
done

mkdir -p "${RUN_DIR}"

ui_running=0
backend_running=0
history_running=0
curl --silent --fail --max-time "${SERVICE_CHECK_TIMEOUT_SECONDS}" "http://${UI_HOST}:${UI_PORT}/" >/dev/null 2>&1 && ui_running=1
curl --silent --fail --max-time "${SERVICE_CHECK_TIMEOUT_SECONDS}" "http://${BACKEND_HOST}:${BACKEND_PORT}/health/live" >/dev/null 2>&1 && backend_running=1
curl --silent --fail --max-time "${SERVICE_CHECK_TIMEOUT_SECONDS}" "http://${HISTORY_HOST}:${HISTORY_PORT}/health/ready" >/dev/null 2>&1 && history_running=1

if (( ui_running && backend_running && history_running )); then
  echo "Rateboard is already running:"
  echo "  UI:      http://${UI_HOST}:${UI_PORT}"
  echo "  Backend: http://${BACKEND_HOST}:${BACKEND_PORT}/docs"
  echo "Run only one copy of scripts/start-all.sh at a time."
  exit 0
fi

if (( ui_running || backend_running || history_running )); then
  echo "Cannot start a second Rateboard copy because some ports are already in use:" >&2
  (( ui_running )) && echo "  UI is already responding on ${UI_HOST}:${UI_PORT}" >&2
  (( backend_running )) && echo "  Backend is already responding on ${BACKEND_HOST}:${BACKEND_PORT}" >&2
  (( history_running )) && echo "  History is already responding on ${HISTORY_HOST}:${HISTORY_PORT}" >&2
  echo "Stop the existing processes or keep using the running application." >&2
  exit 1
fi

if ! pg_isready --dbname="${DATABASE_URL}" >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1 && brew list postgresql@16 >/dev/null 2>&1; then
    echo "Starting PostgreSQL 16..."
    brew services start postgresql@16 >/dev/null
  else
    echo "PostgreSQL is not ready. Start it and run this script again." >&2
    exit 1
  fi
fi

cleanup() {
  trap - INT TERM EXIT
  echo
  echo "Stopping Rateboard..."

  local pids=()
  [[ -n "${UI_PID:-}" ]] && pids+=("${UI_PID}")
  [[ -n "${BACKEND_PID:-}" ]] && pids+=("${BACKEND_PID}")
  [[ -n "${HISTORY_PID:-}" ]] && pids+=("${HISTORY_PID}")

  local pid
  for pid in "${pids[@]}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done

  local attempt
  for (( attempt = 1; attempt <= SERVICE_STOP_ATTEMPTS; attempt++ )); do
    local running=0
    for pid in "${pids[@]}"; do
      if kill -0 "${pid}" 2>/dev/null; then
        running=1
        break
      fi
    done
    (( running == 0 )) && break
    sleep "${SERVICE_STOP_INTERVAL_SECONDS}"
  done

  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      echo "Process ${pid} did not stop in time; sending KILL."
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done

  for pid in "${pids[@]}"; do
    wait "${pid}" 2>/dev/null || true
  done
  echo "Rateboard stopped."
}
trap cleanup INT TERM EXIT

wait_for_url() {
  local url="$1"
  local service="$2"
  local attempts="${SERVICE_START_ATTEMPTS}"
  while (( attempts > 0 )); do
    if curl --silent --fail --max-time "${SERVICE_CHECK_TIMEOUT_SECONDS}" "${url}" >/dev/null 2>&1; then return 0; fi
    attempts=$((attempts - 1))
    sleep "${SERVICE_START_INTERVAL_SECONDS}"
  done
  echo "${service} did not become ready. Check ${RUN_DIR}/${service}.log" >&2
  return 1
}

echo "Applying PostgreSQL migration..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/history-service/migrations/001_init.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/history-service/migrations/002_sampling.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/history-service/migrations/003_backfill_timestamps.sql"

echo "Preparing History service..."
(cd "${ROOT_DIR}/history-service" && go mod download)
(cd "${ROOT_DIR}/history-service" && go build -o "${RUN_DIR}/history-service" ./cmd/server)
(cd "${ROOT_DIR}/history-service" && exec "${RUN_DIR}/history-service") >"${RUN_DIR}/history.log" 2>&1 &
HISTORY_PID=$!
wait_for_url "http://${HISTORY_HOST}:${HISTORY_PORT}/health/ready" history

if [[ ! -x "${ROOT_DIR}/backend-service/.venv/bin/uvicorn" ]]; then
  echo "Preparing Backend virtual environment..."
  python3 -m venv "${ROOT_DIR}/backend-service/.venv"
  "${ROOT_DIR}/backend-service/.venv/bin/pip" install -e "${ROOT_DIR}/backend-service[dev]"
fi

echo "Starting Backend..."
(cd "${ROOT_DIR}/backend-service" && exec .venv/bin/uvicorn app.main:app --host "${BACKEND_HOST}" --port "${BACKEND_PORT}") >"${RUN_DIR}/backend.log" 2>&1 &
BACKEND_PID=$!
wait_for_url "http://${BACKEND_HOST}:${BACKEND_PORT}/health/live" backend

echo "Starting UI..."
(cd "${ROOT_DIR}/ui-service/public" && exec python3 -m http.server "${UI_PORT}" --bind "${UI_HOST}") >"${RUN_DIR}/ui.log" 2>&1 &
UI_PID=$!
wait_for_url "http://${UI_HOST}:${UI_PORT}/" ui

if [[ "${BACKFILL_YEAR_ON_START}" == "1" ]]; then
  "${ROOT_DIR}/scripts/backfill-year.sh"
fi

echo "Rateboard is running:"
echo "  UI:      http://${UI_HOST}:${UI_PORT}"
echo "  Backend: http://${BACKEND_HOST}:${BACKEND_PORT}/docs"
echo "  Logs:    ${RUN_DIR}"
echo "Press Ctrl+C to stop all services."
wait
