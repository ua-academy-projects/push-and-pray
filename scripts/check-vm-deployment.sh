#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

check_compose() {
  local machine="$1"
  local compose_file="$2"
  local service_env="${3:-}"
  local env_args="--env-file /etc/rateboard/alloy.env"
  local required_env
  local required_env_files=(/etc/rateboard/alloy.env)
  if [[ -n "${service_env}" ]]; then
    required_env_files+=("${service_env}")
  fi
  for required_env in "${required_env_files[@]}"; do
    if ! vagrant ssh "${machine}" -c "sudo test -f ${required_env}" >/dev/null 2>&1; then
      echo "${machine}: missing ${required_env}. Run: sudo vagrant rsync ${machine} && sudo vagrant provision ${machine}" >&2
      return 1
    fi
  done
  if [[ -n "${service_env}" ]]; then
    env_args="--env-file ${service_env} ${env_args}"
  fi
  vagrant ssh "${machine}" -c "sudo docker compose ${env_args} -f ${compose_file} ps"
}

vagrant status
check_compose logs /vagrant/infra/docker/logs/compose.yml /etc/rateboard/logs.env
check_compose database /vagrant/infra/docker/database/compose.yml /etc/rateboard/database.env
check_compose rabbitmq /vagrant/infra/docker/rabbitmq/compose.yml /etc/rateboard/rabbitmq.env
check_compose backend-service /vagrant/infra/docker/backend-service/compose.yml /etc/rateboard/backend-service.env
check_compose api-fetcher /vagrant/infra/docker/api-fetcher/compose.yml /etc/rateboard/api-fetcher.env
check_compose ui /vagrant/infra/docker/ui/compose.yml /etc/rateboard/ui.env

# shellcheck disable=SC1091
source .env.vagrant.local
logs_netrc="$(mktemp)"
trap 'rm -f "${logs_netrc}"' EXIT
printf 'machine rates-logs login %s password %s\n' \
  "${RATEBOARD_LOGS_INGEST_USER}" "${RATEBOARD_LOGS_INGEST_PASSWORD}" > "${logs_netrc}"
chmod 0600 "${logs_netrc}"

wait_for_url() {
  local url="$1"
  local curl_extra="${2:-}"
  for attempt in {1..60}; do
    # shellcheck disable=SC2086
    if curl ${curl_extra} --fail --silent --show-error --max-time 3 "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ${url}" >&2
  return 1
}

wait_for_url "http://${RATEBOARD_BACKEND_SERVICE_IP}:${BACKEND_SERVICE_PORT:-8081}/health/ready"
wait_for_url "http://${RATEBOARD_API_FETCHER_IP}:${API_FETCHER_PORT:-8000}/health/ready"
wait_for_url "https://${RATEBOARD_UI_IP}/" "--insecure"
wait_for_url "https://rates-logs/api/health" "--cacert infra/vagrant/generated/logs-tls/ca.crt --resolve rates-logs:443:${RATEBOARD_LOGS_IP}"
wait_for_url "https://rates-logs/loki-ready" "--cacert infra/vagrant/generated/logs-tls/ca.crt --resolve rates-logs:443:${RATEBOARD_LOGS_IP}"

vagrant ssh database -c \
  'sudo docker compose --env-file /etc/rateboard/alloy.env -f /vagrant/infra/docker/database/compose.yml exec -T postgres pg_isready -U rates -d rates'
vagrant ssh rabbitmq -c \
  'sudo docker compose --env-file /etc/rateboard/alloy.env -f /vagrant/infra/docker/rabbitmq/compose.yml exec -T rabbitmq rabbitmq-diagnostics -q ping'

for machine in logs database rabbitmq backend-service api-fetcher ui; do
  vagrant ssh "${machine}" -c \
    'id admin >/dev/null && sudo -u admin sudo -n true && id -nG admin | grep -qw docker'
done

local_user="${SUDO_USER:-}"
if [[ -n "${local_user}" && "${local_user}" != root ]]; then
  for alias_name in logs database rabbitmq backend-service api-fetcher ui; do
    connected_user="$(sudo -H -u "${local_user}" ssh -o BatchMode=yes -o ConnectTimeout=5 \
      "${alias_name}" 'id -un')"
    [[ "${connected_user}" == admin ]] || {
      echo "SSH alias ${alias_name} connected as ${connected_user}, expected admin" >&2
      exit 1
    }
  done
fi

unauthorized_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --cacert infra/vagrant/generated/logs-tls/ca.crt \
  --resolve "rates-logs:443:${RATEBOARD_LOGS_IP}" \
  --request POST --data '{}' \
  https://rates-logs/loki/api/v1/push)"
[[ "${unauthorized_status}" == 401 ]] || {
  echo "Loki ingestion without credentials returned ${unauthorized_status}, expected 401" >&2
  exit 1
}

marker="rateboard-log-check-$(date +%s)"
for machine in logs database rabbitmq backend-service api-fetcher ui; do
  vagrant ssh "${machine}" -c "logger -t rateboard-log-check '${marker}-${machine}'"
done

for attempt in {1..30}; do
  if ! query_result="$(curl --fail --silent --show-error --get \
      --cacert infra/vagrant/generated/logs-tls/ca.crt \
      --resolve "rates-logs:443:${RATEBOARD_LOGS_IP}" \
      --netrc-file "${logs_netrc}" \
      --data-urlencode 'query={service="rateboard-log-check"}' \
      --data-urlencode 'limit=100' \
      https://rates-logs/loki/api/v1/query_range)"; then
    echo "Loki query failed. Inspect Nginx and Loki with: ssh logs 'sudo docker compose --env-file /etc/rateboard/logs.env --env-file /etc/rateboard/alloy.env -f /vagrant/infra/docker/logs/compose.yml logs --tail=100 nginx loki'" >&2
    exit 1
  fi
  all_found=true
  for machine in logs database rabbitmq backend-service api-fetcher ui; do
    [[ "${query_result}" == *"${marker}-${machine}"* ]] || all_found=false
  done
  [[ "${all_found}" == true ]] && break
  if [[ "${attempt}" -eq 30 ]]; then
    echo "Timed out waiting for six VM journal markers in Loki" >&2
    exit 1
  fi
  sleep 2
done

echo
echo "All six VM Compose projects, public health endpoints, SSH admin accounts, and the Loki log path are responding."
