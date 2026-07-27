#!/usr/bin/env bash
set -euo pipefail

readonly UI_URL="http://192.168.100.10:8000"

if ! command -v curl >/dev/null 2>&1; then
  echo "Aegis UI host verification failed: curl is not installed" >&2
  exit 1
fi

attempts=30
while (( attempts > 0 )); do
  if curl --fail --silent --show-error --connect-timeout 2 --max-time 3 \
    "${UI_URL}/health/live" >/dev/null 2>&1; then
    echo "Host can reach ${UI_URL}"
    exit 0
  fi
  attempts=$((attempts - 1))
  sleep 2
done

echo "Aegis UI host verification failed: cannot reach ${UI_URL}" >&2
exit 1
