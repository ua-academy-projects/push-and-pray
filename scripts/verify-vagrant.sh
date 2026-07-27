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
      "sudo systemctl start aegis-provider-blacklist-worker.service" \
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

unit_runs_as_aegis() {
  local vm="$1"
  local unit="$2"
  local owner
  owner="$(timeout 30 vagrant ssh "${vm}" -c \
    "pid=\$(sudo systemctl show --property MainPID --value '${unit}'); test \"\${pid}\" -gt 0; ps -o user= -p \"\${pid}\"" \
    2>/dev/null | tr -d '[:space:]')"
  [[ "${owner}" == "aegis" ]]
}

no_root_application_process() {
  local vm="$1"
  local entry_point="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "ps -eo user=,args= | awk '\$1 == \"root\" && index(\$0, \"${entry_point}\") { found=1 } END { exit found }'"
}

provider_outbox_is_private() {
  timeout 30 vagrant ssh provider-vm -c \
    "test \"\$(stat -c '%U:%G:%a' /var/lib/aegis-provider)\" = 'aegis:aegis:750' && sudo -u aegis test -r /var/lib/aegis-provider && sudo -u aegis test -w /var/lib/aegis-provider"
}

history_schema_is_current() {
  timeout 30 vagrant ssh history-vm -c \
    "sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; .venv/bin/alembic -c alembic.ini current --check-heads'"
}

environment_excludes_mariadb() {
  local vm="$1"
  local environment_file="$2"
  timeout 30 vagrant ssh "${vm}" -c \
    "sudo test -r '${environment_file}' && ! sudo grep -Eq '^(MARIADB_|DATABASE_URL=)' '${environment_file}'"
}

console_scripts_resolve() {
  timeout 30 vagrant ssh history-vm -c \
    "test -x /opt/aegis/history-service/.venv/bin/aegis-history-blacklist-consumer" &&
    timeout 30 vagrant ssh provider-vm -c \
      "test -x /opt/aegis/provider-service/.venv/bin/aegis-provider-blacklist-worker" &&
    timeout 30 vagrant ssh ui-vm -c \
      "test -x /opt/aegis/ui-service/.venv/bin/uvicorn" &&
    timeout 30 vagrant ssh history-vm -c \
      "test -x /opt/aegis/history-service/.venv/bin/uvicorn" &&
    timeout 30 vagrant ssh provider-vm -c \
      "test -x /opt/aegis/provider-service/.venv/bin/uvicorn"
}

focused_offline_tests() {
  timeout 120 .venv/bin/pytest -q \
    services/provider-service/tests/test_blacklist_worker.py \
    services/provider-service/tests/test_outbox.py \
    services/provider-service/tests/test_rabbitmq_publisher.py \
    services/history-service/tests/test_blacklist_consumer.py \
    services/ui-service/tests/test_theme.py
}

rabbitmq_is_ready() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo rabbitmq-diagnostics -q ping && sudo rabbitmq-diagnostics -q check_running"
}

rabbitmq_topology_exists() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo rabbitmqctl -q list_exchanges -p /aegis name | grep -Fxq aegis.blacklist &&
     sudo rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots &&
     sudo rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots.retry.300 &&
     sudo rabbitmqctl -q list_queues -p /aegis name | grep -Fxq aegis.history.blacklist.snapshots.dead"
}

rabbitmq_consumer_registered() {
  timeout 30 vagrant ssh infra-vm -c \
    "sudo rabbitmqctl -q list_queues -p /aegis name consumers |
     awk '\$1 == \"aegis.history.blacklist.snapshots\" && \$2 >= 1 { found=1 } END { exit !found }'"
}

for vm in infra-vm db-vm provider-vm history-vm ui-vm; do
  check "${vm} is running" vm_is_running "${vm}"
done

for target in \
  "ui-vm:192.168.100.10" \
  "history-vm:192.168.100.11" \
  "provider-vm:192.168.100.12" \
  "db-vm:192.168.100.13" \
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

check "MariaDB systemd unit is active" unit_is_active db-vm mariadb.service
check "RabbitMQ systemd unit is active" unit_is_active infra-vm rabbitmq-server.service
check "RabbitMQ diagnostics report ready" rabbitmq_is_ready
check "RabbitMQ management UI is reachable through host loopback" \
  curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
  http://127.0.0.1:15672/
check "Redis systemd unit is active" unit_is_active infra-vm redis-server.service
check "Redis responds to local PING" timeout 30 vagrant ssh infra-vm -c \
  "redis-cli -h 127.0.0.1 ping | grep -Fxq PONG"
check "Provider systemd unit is active" unit_is_active provider-vm \
  aegis-provider-api.service
check "Provider blacklist worker is active" unit_is_active provider-vm \
  aegis-provider-blacklist-worker.service
check "History systemd unit is active" unit_is_active history-vm \
  aegis-history-api.service
check "History blacklist consumer is active" unit_is_active history-vm \
  aegis-history-blacklist-consumer.service
check "RabbitMQ main, retry, and DLQ topology exists" rabbitmq_topology_exists
check "History consumer is registered on the main queue" \
  rabbitmq_consumer_registered
check "UI systemd unit is active" unit_is_active ui-vm aegis-ui.service
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

check "Provider process runs as aegis" unit_runs_as_aegis provider-vm \
  aegis-provider-api.service
check "Provider blacklist worker runs as aegis" unit_runs_as_aegis provider-vm \
  aegis-provider-blacklist-worker.service
check "Provider outbox directory is private and writable" \
  provider_outbox_is_private
check "Application console scripts resolve in service virtual environments" \
  console_scripts_resolve
check "History process runs as aegis" unit_runs_as_aegis history-vm \
  aegis-history-api.service
check "History blacklist consumer runs as aegis" unit_runs_as_aegis history-vm \
  aegis-history-blacklist-consumer.service
check "UI process runs as aegis" unit_runs_as_aegis ui-vm aegis-ui.service
check "No Provider application process runs as root" \
  no_root_application_process provider-vm provider_service.main:app
check "No History application process runs as root" \
  no_root_application_process history-vm history_service.main:app
check "No UI application process runs as root" \
  no_root_application_process ui-vm ui_service.main:app

check "Focused offline unit and contract tests" focused_offline_tests

if [[ "${live_abuseipdb}" == true ]]; then
  live_result=""
  delivery_id=""
  if unit_is_active provider-vm aegis-provider-blacklist-worker.service; then
    provider_was_active=true
  fi
  if timeout 30 vagrant ssh provider-vm -c \
    "sudo systemctl stop aegis-provider-blacklist-worker.service" >/dev/null 2>&1; then
    live_worker_stopped=true
  else
    fail "Could not stop Provider worker for single-request live mode"
  fi

  if [[ "${live_worker_stopped}" == true ]]; then
    live_result="$(timeout 180 vagrant ssh provider-vm -c \
      "sudo -u aegis bash -c 'set -a; source /etc/aegis/provider.env; cd /opt/aegis/provider-service; exec .venv/bin/python /vagrant/scripts/live-blacklist-smoke.py'" \
      2>/dev/null | tr -d '\r' | tail -n 1)" || true
  fi
  if [[ "${provider_was_active}" == true ]]; then
    timeout 30 vagrant ssh provider-vm -c \
      "sudo systemctl start aegis-provider-blacklist-worker.service" >/dev/null 2>&1 || \
      fail "Could not restart Provider worker after live mode"
    live_worker_stopped=false
  fi

  if delivery_id="$(jq -er '.delivery_id' <<<"${live_result}" 2>/dev/null)"; then
    pass "Exactly one live blacklist request produced delivery ${delivery_id}"
    remaining="$(jq -r '.rate_limit_remaining // \"unavailable\"' <<<"${live_result}")"
    printf 'INFO  AbuseIPDB remaining rate limit: %s\n' "${remaining}"
  else
    fail "Live blacklist request/outbox/publisher-confirm step failed"
  fi

  if [[ -n "${delivery_id}" ]]; then
    persisted=false
    acked=false
    for _attempt in {1..30}; do
      if timeout 30 vagrant ssh history-vm -c \
        "sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; exec .venv/bin/python /vagrant/scripts/check-history-delivery.py \"${delivery_id}\"'" \
        >/dev/null 2>&1; then
        persisted=true
      fi
      if timeout 30 vagrant ssh history-vm -c \
        "sudo journalctl -u aegis-history-blacklist-consumer.service --since '-5 minutes' --no-pager | grep -F 'history_blacklist_message_acked delivery_id=${delivery_id}'" \
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
