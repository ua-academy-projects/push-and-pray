#!/usr/bin/env bash
# Deploy OilScope workloads and collect remote diagnostics on any failure.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_CONFIG="$ROOT_DIR/ansible.cfg"
INVENTORY_FILE="$ROOT_DIR/infrastructure/ansible/inventory/oilscope.yml"
TERRAFORM_DIR="$ROOT_DIR/infrastructure/terraform"
SCHEMA_FILE="$TERRAFORM_DIR/project-config.schema.json"
PROJECT_CONFIG="${1:-${OILSCOPE_PROJECT_CONFIG:-}}"
CONNECTION_FILE=""

log() {
  printf '\n==> %s\n' "$1"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup() {
  [[ -z "$CONNECTION_FILE" ]] || rm -f "$CONNECTION_FILE"
}

collect_diagnostics() {
  log "Deployment failed; collecting remote diagnostics"

  # These commands deliberately always finish with success: a second broken
  # host must not hide logs from the first one that failed.
  # The single-quoted script is evaluated by each remote shell, not locally.
  # shellcheck disable=SC2016
  ansible all -i "$INVENTORY_FILE" \
    -e "project_config_path=$PROJECT_CONFIG" \
    --become -m ansible.builtin.shell -a '
    echo "===== host ====="
    hostname || true
    echo "===== oilscope deploy unit ====="
    systemctl status oilscope-deploy.service --no-pager || true
    echo "===== oilscope deploy journal (last 100 lines) ====="
    journalctl -u oilscope-deploy.service -n 100 --no-pager || true
    if command -v docker >/dev/null 2>&1; then
      echo "===== Compose containers ====="
      docker ps -a --filter label=com.docker.compose.project || true
      echo "===== Compose container logs (last 100 lines) ====="
      for container in $(docker ps -aq --filter label=com.docker.compose.project); do
        echo "===== container $container ====="
        docker logs --tail=100 "$container" 2>&1 || true
      done
    else
      echo "Docker is not installed on this host."
    fi
    exit 0
  ' || true
}

on_error() {
  local exit_code=$?
  trap - ERR
  set +e
  collect_diagnostics
  cleanup
  exit "$exit_code"
}

check_group() {
  local group=$1
  local description=$2
  local command=$3

  log "Health check: $description"
  ansible "$group" -i "$INVENTORY_FILE" \
    -e "project_config_path=$PROJECT_CONFIG" \
    --become \
    -m ansible.builtin.shell -a "$command"
}

[[ -n "$PROJECT_CONFIG" ]] || die "Pass a config path: $0 /absolute/path/to/dev.json"
[[ -f "$PROJECT_CONFIG" ]] || die "Project config does not exist: $PROJECT_CONFIG"
PROJECT_CONFIG="$(cd "$(dirname "$PROJECT_CONFIG")" && pwd)/$(basename "$PROJECT_CONFIG")"

require_command ansible
require_command ansible-playbook
require_command jq
require_command terraform

trap cleanup EXIT
trap on_error ERR

export OILSCOPE_PROJECT_CONFIG="$PROJECT_CONFIG"

log "Validating project JSON"
jq empty "$PROJECT_CONFIG"
if command -v check-jsonschema >/dev/null 2>&1; then
  check-jsonschema --schemafile "$SCHEMA_FILE" "$PROJECT_CONFIG"
else
  printf 'Note: check-jsonschema is not installed; skipped JSON Schema validation.\n' >&2
fi

log "Checking Ansible connectivity"
ansible all -i "$INVENTORY_FILE" \
  -e "project_config_path=$PROJECT_CONFIG" \
  -m ansible.builtin.ping

CONNECTION_FILE="$(mktemp "${TMPDIR:-/tmp}/oilscope-connections.XXXXXX.json")"
log "Reading non-secret Terraform connection outputs"
terraform -chdir="$TERRAFORM_DIR" output -json \
  | jq -e '{
      database_connection: .database_connection.value,
      messaging_connection: .messaging_connection.value,
      session_connection: .session_connection.value
    }' > "$CONNECTION_FILE"

DATABASE_MODE="$(jq -r '.database_connection.mode' "$CONNECTION_FILE")"

log "Deploying workloads in dependency order"
ansible-playbook oilscope.platform.deploy_workloads \
  -i "$INVENTORY_FILE" \
  -e "project_config_path=$PROJECT_CONFIG" \
  -e "@$CONNECTION_FILE"

if [[ "$DATABASE_MODE" == "self_managed" ]]; then
  check_group database "PostgreSQL accepts connections" \
    'docker compose -f /opt/oilscope/app/compose.yaml exec -T postgres pg_isready -U oil_tracker -d oil_tracker'
fi

check_group history "History API /health" \
  'curl --fail --silent --show-error http://127.0.0.1:8001/health'

check_group fetcher "Fetcher API /health" \
  'curl --fail --silent --show-error http://127.0.0.1:8002/health'

check_group ui "UI through the HTTPS proxy /health" \
  'curl --fail --silent --show-error --insecure https://127.0.0.1/health'

log "Deployment and all health checks succeeded"
