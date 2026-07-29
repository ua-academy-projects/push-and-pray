#!/usr/bin/env bash
set -euo pipefail

readonly UI_URL="http://192.168.100.10:8000"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
cookie_jar="$(mktemp)"
session_id=""

cd "${REPOSITORY_ROOT}"

cleanup() {
  rm -f "${cookie_jar}"
  vagrant ssh infra-vm -c "sudo docker start aegis-redis" >/dev/null 2>&1 || true
  if [[ -n "${session_id}" ]]; then
    redis_guest "DEL theme:${session_id}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fail() {
  echo "Redis theme smoke test failed: $*" >&2
  exit 1
}

redis_guest() {
  local command="$1"
  vagrant ssh infra-vm -c \
    "sudo docker exec aegis-redis sh -c 'REDISCLI_AUTH=\$(sed -n \"s/^user aegis_ui .* >\\\\([^ ]*\\\\).*/\\\\1/p\" /usr/local/etc/redis/users.acl) redis-cli --no-auth-warning --user aegis_ui --raw ${command}'"
}

curl --fail --silent --show-error --cookie-jar "${cookie_jar}" \
  "${UI_URL}/theme" >/dev/null
session_id="$(awk '$6 == "theme_session" { print $7; exit }' "${cookie_jar}")"
[[ -n "${session_id}" ]] || fail "UI did not issue its anonymous session cookie"

curl --fail --silent --show-error --cookie "${cookie_jar}" \
  --cookie-jar "${cookie_jar}" --request POST --data 'theme=light' \
  "${UI_URL}/theme" >/dev/null

stored_theme="$(redis_guest "GET theme:${session_id}" 2>/dev/null | tr -d '\r')"
[[ "${stored_theme}" == "light" ]] || fail "Redis did not contain the UI-written theme"

ttl="$(redis_guest "TTL theme:${session_id}" 2>/dev/null | tr -d '[:space:]')"
[[ "${ttl}" =~ ^[0-9]+$ ]] && (( ttl > 0 )) || fail "theme key has no positive TTL"

# A graceful Redis restart exercises the selected RDB persistence behavior.
vagrant ssh infra-vm -c "sudo docker restart aegis-redis" >/dev/null
redis_guest PING | grep -Fxq PONG
[[ "$(redis_guest "GET theme:${session_id}" 2>/dev/null | tr -d '\r')" == "light" ]] || \
  fail "theme did not survive a graceful Redis restart"

vagrant ssh ui-vm -c "sudo docker restart aegis-ui" >/dev/null
response="$(curl --fail --silent --show-error --cookie "${cookie_jar}" \
  "${UI_URL}/theme")"
[[ "${response}" == '{"theme":"light"}' ]] || fail "theme did not survive a UI restart"

# Redis loss must degrade theme reads to the implemented dark default while
# keeping UI pages and the theme endpoint available.
vagrant ssh infra-vm -c "sudo docker stop aegis-redis" >/dev/null
response="$(curl --fail --silent --show-error --max-time 10 \
  --cookie "${cookie_jar}" "${UI_URL}/theme")"
[[ "${response}" == '{"theme":"dark"}' ]] || \
  fail "UI did not fall back to the dark default while Redis was unavailable"
curl --fail --silent --show-error --max-time 10 \
  --cookie "${cookie_jar}" "${UI_URL}/" >/dev/null

echo "Redis theme persistence, TTL, UI restart, and failure fallback verified"
