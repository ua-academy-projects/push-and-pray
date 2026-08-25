#!/bin/sh
set -eu

ui_health_url="${UI_HEALTH_URL:-http://127.0.0.1:${UI_HTTP_PORT:-80}/health}"
history_health_url="${HISTORY_HEALTH_URL:-http://127.0.0.1:${HISTORY_HOST_PORT:-8001}/health}"
fetcher_health_url="${FETCHER_HEALTH_URL:-http://127.0.0.1:${FETCHER_HOST_PORT:-8002}/health}"

check_health() {
    service="$1"
    url="$2"
    expected="$3"

    response="$(curl --fail --silent --show-error --max-time 10 "${url}")"
    printf '%s: %s\n' "${service}" "${response}"

    if ! printf '%s' "${response}" | grep --fixed-strings --quiet "${expected}"; then
        printf '%s health response does not contain %s\n' "${service}" "${expected}" >&2
        exit 1
    fi
}

check_health ui "${ui_health_url}" '"sessions":"postgresql"'
check_health history "${history_health_url}" '"pgmq_consumer":"ready"'
check_health fetcher "${fetcher_health_url}" '"delivery":"pgmq"'

printf 'Deployment smoke test passed\n'
