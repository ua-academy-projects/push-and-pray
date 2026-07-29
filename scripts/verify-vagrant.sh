#!/usr/bin/env bash
set -uo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"

passed=0
failed=0
live_abuseipdb=false
provider_was_active=false
live_worker_stopped=false

restore_provider_worker() {
  if [[ "${live_worker_stopped}" == true && "${provider_was_active}" == true ]]; then
    timeout 30 vagrant ssh provider-vm -c \
      "sudo docker start aegis-provider-worker" \
      >/dev/null 2>&1 || true
  fi
}
trap restore_provider_worker EXIT

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-vagrant.sh
  scripts/verify-vagrant.sh --live-abuseipdb

The default mode performs offline/local checks only. Live mode performs exactly
one AbuseIPDB blacklist request and traces its delivery; it consumes quota.
EOF
}

case "${1:-}" in
  "")
    ;;
  --live-abuseipdb)
    [[ $# -eq 1 ]] || {
      usage >&2
      exit 2
    }
    live_abuseipdb=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

cd "${REPOSITORY_ROOT}" || exit 2

pass() {
  printf 'PASS  %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failed=$((failed + 1))
}

check() {
  local description="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    pass "${description}"
  else
    fail "${description}"
  fi
}

vm_is_running() {
  local vm="$1"
  local state
  state="$(timeout 30 vagrant status "${vm}" --machine-readable 2>/dev/null | \
    awk -F, '$3 == "state" { print $4; exit }')"
  [[ "${state}" == "running" ]]
}

private_ip_responds() {
  local address="$1"
  timeout 3 bash -c "</dev/tcp/${address}/22"
}

guest_http_ok() {
  local vm="$1"
  local url="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "curl --fail --silent --show-error --connect-timeout 3 --max-time 10 '${url}'"
}

unit_is_active() {
  local vm="$1"
  local unit="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "sudo systemctl is-active --quiet '${unit}'"
}

container_is_healthy() {
  local vm="$1"
  local container="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "test \"\$(sudo docker inspect --format '{{.State.Running}}:{{.State.Health.Status}}' '${container}')\" = true:healthy"
}

container_runs_as_non_root() {
  local vm="$1"
  local container="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "test \"\$(sudo docker inspect --format '{{.Config.User}}' '${container}')\" = 10001:10001"
}

no_host_application_process() {
  local vm="$1"
  timeout 30 vagrant ssh "${vm}" -c \
    "! ps -eo args= | grep -E '[u]vicorn (ui_service|history_service|provider_service)|[a]egis-(history-blacklist-consumer|provider-blacklist-worker)'"
}

history_schema_is_current() {
  timeout 30 vagrant ssh history-vm -c \
    "sudo docker exec aegis-history-api alembic -c /app/alembic.ini current --check-heads"
}

environment_excludes_mariadb() {
  local vm="$1"
  local environment_file="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "sudo test -r '${environment_file}' && ! sudo grep -Eq '^(MARIADB_|DATABASE_URL=)' '${environment_file}'"
}

focused_offline_tests() {
  timeout 120 .venv/bin/pytest -q \
    services/provider-service/tests/test_blacklist_worker.py \
    services/provider-service/tests/test_rabbitmq_publisher.py \
    services/history-service/tests/test_blacklist_consumer.py \
    services/ui-service/tests/test_theme.py
}

rabbitmq_is_ready() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo docker exec aegis-rabbitmq rabbitmq-diagnostics -q ping &&
     sudo docker exec aegis-rabbitmq rabbitmq-diagnostics -q check_running"
}

rabbitmq_topology_exists() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo docker exec aegis-rabbitmq rabbitmqctl -q list_exchanges -p /aegis name | grep -Fxq aegis.blacklist &&
     sudo docker exec aegis-rabbitmq rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots &&
     sudo docker exec aegis-rabbitmq rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots.retry.300 &&
     sudo docker exec aegis-rabbitmq rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots.dead"
}

rabbitmq_consumer_registered() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo docker exec aegis-rabbitmq rabbitmqctl -q list_queues -p /aegis name consumers |
     awk '\$1 == \"aegis.history.blacklist.snapshots\" && \$2 >= 1 { found=1 } END { exit !found }'"
}

for vm in infra-vm provider-vm history-vm ui-vm; do
  check "${vm} is running" vm_is_running "${vm}"
done

for target in \
  "ui-vm:192.168.100.10" \
  "history-vm:192.168.100.11" \
  "provider-vm:192.168.100.12" \
  "infra-vm:192.168.100.14"; do
  vm="${target%%:*}"
  address="${target#*:}"
  check "${vm} private address ${address} responds" private_ip_responds "${address}"
done

check "Provider liveness" guest_http_ok provider-vm \
  http://192.168.100.12:8001/health/live
check "Provider readiness (quota-free)" guest_http_ok provider-vm \
  http://192.168.100.12:8001/health/ready
check "History liveness" guest_http_ok history-vm \
  http://192.168.100.11:8002/health/live
check "History readiness" guest_http_ok history-vm \
  http://192.168.100.11:8002/health/ready
check "UI liveness" curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://192.168.100.10:8000/health/live
check "UI readiness" curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://192.168.100.10:8000/health/ready
check "UI main page from host" curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://192.168.100.10:8000/
check "UI blacklist page from host" curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://192.168.100.10:8000/blacklist
check "History blacklist status" guest_http_ok ui-vm \
  http://192.168.100.11:8002/api/v1/blacklist/status

check "MariaDB container is healthy" container_is_healthy infra-vm aegis-mariadb
check "RabbitMQ container is healthy" container_is_healthy infra-vm aegis-rabbitmq
check "RabbitMQ diagnostics report ready" rabbitmq_is_ready
check "RabbitMQ management UI is reachable on the private network" \
  curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://192.168.100.14:15672/
check "Redis container is healthy" container_is_healthy infra-vm aegis-redis
check "Provider API container is healthy" container_is_healthy provider-vm \
  aegis-provider-api
check "Provider Worker container is healthy" container_is_healthy provider-vm \
  aegis-provider-worker
check "History API container is healthy" container_is_healthy history-vm \
  aegis-history-api
check "History Consumer container is healthy" container_is_healthy history-vm \
  aegis-history-consumer
check "RabbitMQ main, retry, and DLQ topology exists" rabbitmq_topology_exists
check "History consumer is registered on the main queue" \
  rabbitmq_consumer_registered
check "UI container is healthy" container_is_healthy ui-vm aegis-ui
check "UI theme persists and Redis failure falls back safely" \
  scripts/verify-redis-theme-vagrant.sh

# History readiness executes SELECT 1 against its configured MariaDB session.
check "History can read MariaDB" guest_http_ok history-vm \
  http://192.168.100.11:8002/health/ready
check "History MariaDB schema is at the current Alembic head" \
  history_schema_is_current
# UI readiness calls History readiness, proving the UI-to-History path.
check "UI can communicate with History" guest_http_ok ui-vm \
  http://192.168.100.10:8000/health/ready
check "Provider environment has no MariaDB dependency" \
  environment_excludes_mariadb provider-vm /etc/aegis/provider.env
check "UI environment has no MariaDB dependency" \
  environment_excludes_mariadb ui-vm /etc/aegis/ui.env

for target in \
  "provider-vm:aegis-provider-api" \
  "provider-vm:aegis-provider-worker" \
  "history-vm:aegis-history-api" \
  "history-vm:aegis-history-consumer" \
  "ui-vm:aegis-ui"; do
  vm="${target%%:*}"
  container="${target#*:}"
  check "${container} runs as a non-root image user" \
    container_runs_as_non_root "${vm}" "${container}"
done
check "No Provider application process runs on the VM host" \
  no_host_application_process provider-vm
check "No History application process runs on the VM host" \
  no_host_application_process history-vm
check "No UI application process runs on the VM host" \
  no_host_application_process ui-vm

check "Focused offline unit and contract tests" focused_offline_tests

if [[ "${live_abuseipdb}" == true ]]; then
  live_result=""
  delivery_id=""
  if timeout 30 vagrant ssh provider-vm -c \
    "test \"\$(sudo docker inspect --format '{{.State.Running}}' aegis-provider-worker)\" = true"; then
    provider_was_active=true
  fi
  if timeout 30 vagrant ssh provider-vm -c \
    "sudo docker stop aegis-provider-worker" >/dev/null 2>&1; then
    live_worker_stopped=true
  else
    fail "Could not stop Provider worker for single-request live mode"
  fi

  if [[ "${live_worker_stopped}" == true ]]; then
    live_result="$(timeout 180 vagrant ssh provider-vm -c \
      "sudo docker compose -f /vagrant/deploy/provider-vm/compose.yaml run --rm --no-deps --volume /vagrant/scripts:/smoke:ro provider-api python /smoke/live-blacklist-smoke.py" \
      2>/dev/null | tr -d '\r' | tail -n 1)" || true
  fi
  if [[ "${provider_was_active}" == true ]]; then
    timeout 30 vagrant ssh provider-vm -c \
      "sudo docker start aegis-provider-worker" >/dev/null 2>&1 || \
      fail "Could not restart Provider worker after live mode"
    live_worker_stopped=false
  fi

  if delivery_id="$(jq -er '.delivery_id' <<<"${live_result}" 2>/dev/null)"; then
    pass "Exactly one live blacklist request produced delivery ${delivery_id}"
    remaining="$(jq -r '.rate_limit_remaining // \"unavailable\"' <<<"${live_result}")"
    printf 'INFO  AbuseIPDB remaining rate limit: %s\n' "${remaining}"
  else
    fail "Live blacklist request/direct publisher-confirm step failed"
  fi

  if [[ -n "${delivery_id}" ]]; then
    persisted=false
    acked=false
    for _attempt in {1..30}; do
      if timeout 30 vagrant ssh history-vm -c \
        "sudo docker compose -f /vagrant/deploy/history-vm/compose.yaml run --rm --no-deps --volume /vagrant/scripts:/smoke:ro history-api python /smoke/check-history-delivery.py \"${delivery_id}\"" \
        >/dev/null 2>&1; then
        persisted=true
      fi
      if timeout 30 vagrant ssh history-vm -c \
        "sudo docker logs aegis-history-consumer --since 5m 2>&1 | grep -F 'history_blacklist_message_acked delivery_id=${delivery_id}'" \
        >/dev/null 2>&1; then
        acked=true
      fi
      [[ "${persisted}" == true && "${acked}" == true ]] && break
      sleep 2
    done
    [[ "${persisted}" == true ]] && \
      pass "History committed delivery ${delivery_id} to MariaDB" || \
      fail "History did not commit delivery ${delivery_id}"
    [[ "${acked}" == true ]] && \
      pass "History ACKed delivery ${delivery_id}" || \
      fail "History ACK was not observed for delivery ${delivery_id}"
  fi
fi

printf '\nSummary: %d passed, %d failed\n' "${passed}" "${failed}"
(( failed == 0 ))
