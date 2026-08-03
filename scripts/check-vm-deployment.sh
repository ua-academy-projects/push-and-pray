#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

check_compose() {
  local machine="$1"
  local compose_file="$2"
  vagrant ssh "${machine}" -c "sudo docker compose -f ${compose_file} ps"
}

vagrant status
check_compose database /vagrant/infra/docker/database/compose.yml
check_compose rabbitmq /vagrant/infra/docker/rabbitmq/compose.yml
check_compose backend-service /vagrant/infra/docker/backend-service/compose.yml
check_compose api-fetcher /vagrant/infra/docker/api-fetcher/compose.yml
check_compose ui /vagrant/infra/docker/ui/compose.yml

# shellcheck disable=SC1091
source .env.vagrant.local

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

vagrant ssh database -c \
  'sudo docker compose -f /vagrant/infra/docker/database/compose.yml exec -T postgres pg_isready -U rates -d rates'
vagrant ssh rabbitmq -c \
  'sudo docker compose -f /vagrant/infra/docker/rabbitmq/compose.yml exec -T rabbitmq rabbitmq-diagnostics -q ping'

echo
echo "All five VM Compose projects and public health endpoints are responding."
