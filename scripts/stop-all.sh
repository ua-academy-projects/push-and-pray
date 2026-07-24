#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

BACKEND_PORT="${BACKEND_PORT:-8000}"
API_FETCHER_PORT="${API_FETCHER_PORT:-8081}"
UI_PORT="${UI_PORT:-3000}"
PORTS=("${UI_PORT}" "${BACKEND_PORT}" "${API_FETCHER_PORT}")

if ! command -v lsof >/dev/null 2>&1; then
  echo "Required command is not installed: lsof" >&2
  exit 1
fi

pids=()
for port in "${PORTS[@]}"; do
  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    already_added=0
    for known_pid in "${pids[@]:-}"; do
      if [[ "${known_pid}" == "${pid}" ]]; then
        already_added=1
        break
      fi
    done
    (( already_added )) || pids+=("${pid}")
  done < <(lsof -nP -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)
done

if (( ${#pids[@]} == 0 )); then
  echo "Rateboard is already stopped; ports ${UI_PORT}, ${BACKEND_PORT}, and ${API_FETCHER_PORT} are free."
  exit 0
fi

echo "Stopping Rateboard listeners:"
for pid in "${pids[@]}"; do
  command_name="$(ps -p "${pid}" -o command= 2>/dev/null || echo unknown)"
  echo "  PID ${pid}: ${command_name}"
  kill -TERM "${pid}" 2>/dev/null || true
done

for _ in {1..20}; do
  remaining=0
  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      remaining=1
      break
    fi
  done
  (( remaining == 0 )) && break
  sleep 0.25
done

for pid in "${pids[@]}"; do
  if kill -0 "${pid}" 2>/dev/null; then
    echo "PID ${pid} did not stop after 5 seconds; sending KILL."
    kill -KILL "${pid}" 2>/dev/null || true
  fi
done

failed=0
for port in "${PORTS[@]}"; do
  if lsof -nP -t -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port ${port} is still occupied." >&2
    failed=1
  else
    echo "Port ${port} is free."
  fi
done

if (( failed )); then
  exit 1
fi

echo "Rateboard services are stopped. PostgreSQL was left running."
