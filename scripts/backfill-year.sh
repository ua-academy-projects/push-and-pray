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

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}"

if date -u -v-1y +%F >/dev/null 2>&1; then
  FROM_DATE="${BACKFILL_FROM:-$(date -u -v-1y +%F)}"
else
  FROM_DATE="${BACKFILL_FROM:-$(date -u -d '1 year ago' +%F)}"
fi
TO_DATE="${BACKFILL_TO:-$(date -u +%F)}"

INSTRUMENTS='["crypto:bitcoin:usd","crypto:ethereum:usd","crypto:tether:usd","crypto:binancecoin:usd","crypto:solana:usd","crypto:usd-coin:usd","crypto:ripple:usd","crypto:dogecoin:usd","crypto:cardano:usd","crypto:tron:usd","fiat:USD:UAH","fiat:EUR:UAH","fiat:GBP:UAH","fiat:PLN:UAH","fiat:CHF:UAH","fiat:CAD:UAH","fiat:AUD:UAH","fiat:JPY:UAH","fiat:CNY:UAH","fiat:CZK:UAH"]'

echo "Backfilling ${FROM_DATE} through ${TO_DATE}..."
curl --fail-with-body --silent --show-error \
  --request POST "${BACKEND_URL}/api/v1/rates/backfill" \
  --header 'Content-Type: application/json' \
  --data "{\"instruments\":${INSTRUMENTS},\"from_date\":\"${FROM_DATE}\",\"to_date\":\"${TO_DATE}\"}"
echo
echo "Backfill complete. Re-running is safe: duplicate observations are ignored."
