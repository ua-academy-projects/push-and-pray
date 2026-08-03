#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
VAGRANT_ENV_FILE="${ROOT_DIR}/.env.vagrant.local"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ -f "${VAGRANT_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${VAGRANT_ENV_FILE}"
  set +a
fi

API_FETCHER_HOST="${API_FETCHER_HOST:-127.0.0.1}"
API_FETCHER_PORT="${API_FETCHER_PORT:-8000}"
if [[ -n "${API_FETCHER_URL:-}" ]]; then
  API_FETCHER_URL="${API_FETCHER_URL%/}"
elif [[ "${RATEBOARD_NETWORK_MODE:-}" == "vmnet_bridged" && -n "${RATEBOARD_API_FETCHER_IP:-}" ]]; then
  API_FETCHER_URL="http://${RATEBOARD_API_FETCHER_IP}:${API_FETCHER_PORT}"
else
  API_FETCHER_URL="http://${API_FETCHER_HOST}:${API_FETCHER_PORT}"
fi

if date -u -v-1y +%F >/dev/null 2>&1; then
  FROM_DATE="${BACKFILL_FROM:-$(date -u -v-1y +%F)}"
else
  FROM_DATE="${BACKFILL_FROM:-$(date -u -d '1 year ago' +%F)}"
fi
TO_DATE="${BACKFILL_TO:-$(date -u +%F)}"
BACKFILL_TOKEN="${RATEBOARD_INTERNAL_API_TOKEN:-${RATEBOARD_BACKEND_SERVICE_TOKEN:-${INTERNAL_API_TOKEN:-}}}"
: "${BACKFILL_TOKEN:?Set RATEBOARD_INTERNAL_API_TOKEN or INTERNAL_API_TOKEN}"

INSTRUMENTS='["crypto:bitcoin:usd","crypto:ethereum:usd","crypto:tether:usd","crypto:binancecoin:usd","crypto:solana:usd","crypto:usd-coin:usd","crypto:ripple:usd","crypto:dogecoin:usd","crypto:cardano:usd","crypto:tron:usd","fiat:USD:UAH","fiat:EUR:UAH","fiat:GBP:UAH","fiat:PLN:UAH","fiat:CHF:UAH","fiat:CAD:UAH","fiat:AUD:UAH","fiat:JPY:UAH","fiat:CNY:UAH","fiat:CZK:UAH"]'

echo "Checking API Fetcher at ${API_FETCHER_URL}..."
curl --fail-with-body --silent --show-error \
  --max-time 5 \
  "${API_FETCHER_URL}/health/ready" >/dev/null

echo "Backfilling ${FROM_DATE} through ${TO_DATE}..."
response="$(curl --fail-with-body --silent --show-error \
  --request POST "${API_FETCHER_URL}/internal/v1/backfill" \
  --header "Authorization: Bearer ${BACKFILL_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "{\"instruments\":${INSTRUMENTS},\"from_date\":\"${FROM_DATE}\",\"to_date\":\"${TO_DATE}\"}")"
printf '%s\n' "${response}"

python3 -c '
import json
import sys

payload = json.load(sys.stdin)
failed = [item for item in payload.get("results", []) if item.get("persistence_status") == "failed"]
if failed:
    names = ", ".join(item.get("instrument_id", "unknown") for item in failed)
    raise SystemExit(f"Backfill failed for: {names}")
' <<<"${response}"

echo "Backfill events were accepted by RabbitMQ; History Service writes them to PostgreSQL."
echo "Re-running is safe: duplicate observations are ignored."
