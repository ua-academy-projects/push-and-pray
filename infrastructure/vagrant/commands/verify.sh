#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"

failures=0

check_ssh_alias() {
  local alias_name="$1"
  local actual_user=""
  actual_user="$(ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "${alias_name}" \
    'id -un' 2>/dev/null || true)"
  if [[ "${actual_user}" == "${SSH_ADMIN_USER}" ]]; then
    printf 'PASS  SSH alias %-8s user=%s\n' "${alias_name}" "${actual_user}"
  else
    printf 'FAIL  SSH alias %-8s returned user=%s\n' \
      "${alias_name}" "${actual_user:-unreachable}" >&2
    failures=$((failures + 1))
  fi
}

check_http() {
  local label="$1"
  local url="$2"
  if curl -fsS --max-time 10 "${url}" >/dev/null; then
    printf 'PASS  %s  %s\n' "${label}" "${url}"
  else
    printf 'FAIL  %s  %s\n' "${label}" "${url}" >&2
    failures=$((failures + 1))
  fi
}

check_docker_daemon() {
  local machine="$1"
  if run_vagrant ssh "${machine}" -c \
    'sudo systemctl is-active --quiet docker && sudo docker compose version >/dev/null' \
    >/dev/null 2>&1; then
    printf 'PASS  %-10s Docker Engine + Compose plugin\n' "${machine}"
  else
    printf 'FAIL  %-10s Docker Engine or Compose plugin\n' "${machine}" >&2
    failures=$((failures + 1))
  fi
}

check_compose_service() {
  local machine="$1"
  local role="$2"
  local service="$3"
  if run_vagrant ssh "${machine}" -c \
    "sudo docker compose \
      --env-file /etc/oil-price-tracker/docker.env \
      --file /opt/oil-price-tracker/source/infrastructure/docker/compose.${role}.yaml \
      --project-name petroscope-${role} \
      ps --status running --services | grep -Fxq ${service}" \
    >/dev/null 2>&1; then
    printf 'PASS  %-10s compose:%s\n' "${machine}" "${service}"
  else
    printf 'FAIL  %-10s compose:%s\n' "${machine}" "${service}" >&2
    failures=$((failures + 1))
  fi
}

check_journald_logging() {
  local machine="$1"
  local role="$2"
  local service="$3"
  local container_id=""
  local logging_driver=""
  container_id="$(run_vagrant ssh "${machine}" -c \
    "sudo docker compose \
      --env-file /etc/oil-price-tracker/docker.env \
      --file /opt/oil-price-tracker/source/infrastructure/docker/compose.${role}.yaml \
      --project-name petroscope-${role} \
      ps --quiet ${service}" 2>/dev/null || true)"
  container_id="${container_id//$'\r'/}"
  if [[ -n "${container_id}" ]]; then
    logging_driver="$(run_vagrant ssh "${machine}" -c \
      "sudo docker inspect --format '{{.HostConfig.LogConfig.Type}}' ${container_id}" \
      2>/dev/null || true)"
    logging_driver="${logging_driver//$'\r'/}"
  fi
  if [[ "${logging_driver}" == "journald" ]]; then
    printf 'PASS  %-10s journald:%s\n' "${machine}" "${service}"
  else
    printf 'FAIL  %-10s logging:%s driver=%s\n' \
      "${machine}" "${service}" "${logging_driver:-unknown}" >&2
    failures=$((failures + 1))
  fi
}

for machine in database history fetcher ui; do
  check_docker_daemon "${machine}"
done

check_compose_service database database postgres
check_compose_service history history rabbitmq
check_compose_service history history history
check_compose_service fetcher fetcher fetcher
check_compose_service ui ui ui

check_journald_logging database database postgres
check_journald_logging history history rabbitmq
check_journald_logging history history history
check_journald_logging fetcher fetcher fetcher
check_journald_logging ui ui ui

check_ssh_alias database
check_ssh_alias history
check_ssh_alias worker
check_ssh_alias app

db_ip="$(lan_ip_for database)"
history_ip="$(lan_ip_for history)"
fetcher_ip="$(lan_ip_for fetcher)"
ui_ip="$(lan_ip_for ui)"

if nc -z -w 5 "${db_ip}" 5432; then
  printf 'PASS  PostgreSQL LAN socket  %s:5432\n' "${db_ip}"
else
  printf 'FAIL  PostgreSQL LAN socket  %s:5432\n' "${db_ip}" >&2
  failures=$((failures + 1))
fi

if nc -z -w 5 "${history_ip}" 5672; then
  printf 'PASS  RabbitMQ AMQP socket   %s:5672\n' "${history_ip}"
else
  printf 'FAIL  RabbitMQ AMQP socket   %s:5672\n' "${history_ip}" >&2
  failures=$((failures + 1))
fi

check_http 'History health' "http://${history_ip}:8001/health"
check_http 'Fetcher health' "http://${fetcher_ip}:8002/health"
check_http 'UI health' "http://${ui_ip}:8080/health"
check_http 'UI page' "http://${ui_ip}:8080/"
check_http 'Saved data through UI' "http://${ui_ip}:8080/api/latest"
check_http 'PostgreSQL-backed UI session' "http://${ui_ip}:8080/api/session/preferences"

history_rabbit="$(curl -fsS --max-time 10 "http://${history_ip}:8001/health" \
  | jq -r '.rabbitmq // empty' || true)"
if [[ "${history_rabbit}" == "connected" ]]; then
  printf 'PASS  History consumes RabbitMQ events\n'
else
  printf 'FAIL  History RabbitMQ state: %s\n' "${history_rabbit:-unknown}" >&2
  failures=$((failures + 1))
fi

rabbit_queues="$(run_vagrant ssh history -c \
  'sudo docker compose \
    --env-file /etc/oil-price-tracker/docker.env \
    --file /opt/oil-price-tracker/source/infrastructure/docker/compose.history.yaml \
    --project-name petroscope-history \
    exec -T rabbitmq \
    rabbitmqctl -q list_queues -p oil_tracker name consumers messages_ready' \
  2>/dev/null || true)"
if awk '$1 == "history.price-observations" && $2 >= 1 { found=1 } END { exit !found }' \
  <<< "${rabbit_queues}"; then
  printf 'PASS  Durable queue has an active History consumer\n'
else
  printf 'FAIL  RabbitMQ queue/consumer is not ready\n' >&2
  failures=$((failures + 1))
fi

schema_columns="$(run_vagrant ssh database -c \
  'sudo docker compose \
    --env-file /etc/oil-price-tracker/docker.env \
    --file /opt/oil-price-tracker/source/infrastructure/docker/compose.database.yaml \
    --project-name petroscope-database \
    exec -T postgres \
    psql -U oil_tracker -d oil_tracker -Atc \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='\''price_observations'\'' AND column_name='\''source_observed_at'\''"' \
  2>/dev/null || true)"
# vagrant ssh may return CRLF even though the SQL value itself is just "1".
schema_columns="${schema_columns//$'\r'/}"
if [[ "${schema_columns}" == "1" ]]; then
  printf 'PASS  PostgreSQL migrations are applied\n'
else
  printf 'FAIL  PostgreSQL schema migration check returned: %s\n' "${schema_columns:-empty}" >&2
  failures=$((failures + 1))
fi

session_extensions="$(run_vagrant ssh database -c \
  'sudo docker compose \
    --env-file /etc/oil-price-tracker/docker.env \
    --file /opt/oil-price-tracker/source/infrastructure/docker/compose.database.yaml \
    --project-name petroscope-database \
    exec -T postgres \
    psql -U oil_tracker -d oil_tracker -Atc \
    "SELECT count(*) FROM pg_extension WHERE extname IN ('\''pg_cron'\'', '\''pgcrypto'\''); \
     SELECT count(*) FROM cron.job WHERE jobname = '\''delete-expired-ui-sessions'\'' AND active"' \
  2>/dev/null || true)"
session_extensions="${session_extensions//$'\r'/}"
if [[ "${session_extensions}" == $'2\n1' ]]; then
  printf 'PASS  PostgreSQL session extensions and cleanup job are active\n'
else
  printf 'FAIL  PostgreSQL session extension check returned: %s\n' \
    "${session_extensions:-empty}" >&2
  failures=$((failures + 1))
fi

fetcher_error="$(curl -fsS --max-time 10 "http://${fetcher_ip}:8002/health" \
  | jq -r '.last_error // empty' || true)"
if [[ -n "${fetcher_error}" ]]; then
  printf 'FAIL  Fetcher last_error: %s\n' "${fetcher_error}" >&2
  failures=$((failures + 1))
else
  printf 'PASS  Fetcher has no recorded error\n'
fi

if ((failures > 0)); then
  printf '\nVerification failed: %d check(s).\n' "${failures}" >&2
  exit 1
fi

printf '\nAll Docker Compose services communicate successfully across the Vagrant VMs.\n'
