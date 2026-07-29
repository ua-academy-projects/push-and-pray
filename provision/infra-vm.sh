#!/usr/bin/env bash
set -euo pipefail

readonly DATABASE_PASSWORD_FILE="/tmp/aegis-mariadb-password"
readonly DATABASE_ROOT_PASSWORD_FILE="/tmp/aegis-mariadb-root-password"
readonly PROVIDER_PASSWORD_FILE="/tmp/aegis-rabbitmq-provider-password"
readonly HISTORY_PASSWORD_FILE="/tmp/aegis-rabbitmq-history-password"
readonly ADMIN_PASSWORD_FILE="/tmp/aegis-rabbitmq-admin-password"
readonly REDIS_PASSWORD_FILE="/tmp/aegis-redis-password"
readonly ENVIRONMENT_DIRECTORY="/etc/aegis"
readonly ENVIRONMENT_FILE="${ENVIRONMENT_DIRECTORY}/infra.env"
readonly DEFINITIONS_FILE="${ENVIRONMENT_DIRECTORY}/rabbitmq-definitions.json"
readonly REDIS_ACL_FILE="${ENVIRONMENT_DIRECTORY}/redis-users.acl"
readonly COMPOSE_FILE="/vagrant/deploy/infra-vm/compose.yaml"

fail() {
  echo "Aegis infrastructure provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis infrastructure: $*"
}

secret_files=(
  "${DATABASE_PASSWORD_FILE}"
  "${DATABASE_ROOT_PASSWORD_FILE}"
  "${PROVIDER_PASSWORD_FILE}"
  "${HISTORY_PASSWORD_FILE}"
  "${ADMIN_PASSWORD_FILE}"
  "${REDIS_PASSWORD_FILE}"
)
for secret_file in "${secret_files[@]}"; do
  [[ -f "${secret_file}" ]] || fail "missing credential upload: ${secret_file}"
done
[[ -f "${COMPOSE_FILE}" ]] || fail "missing infrastructure Compose definition"

cleanup() {
  rm -f "${secret_files[@]}" "${temporary_environment:-}" \
    "${temporary_definitions:-}" "${temporary_acl:-}"
}
trap cleanup EXIT

read_secret() {
  local secret_file="$1"
  local value
  value="$(<"${secret_file}")"
  [[ -n "${value}" ]] || fail "${secret_file} must not be empty"
  [[ "${value}" != *$'\n'* ]] || fail "${secret_file} must contain exactly one line"
  [[ "${value}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
    fail "${secret_file} contains unsupported characters"
  printf '%s' "${value}"
}

database_password="$(read_secret "${DATABASE_PASSWORD_FILE}")"
database_root_password="$(read_secret "${DATABASE_ROOT_PASSWORD_FILE}")"
provider_password="$(read_secret "${PROVIDER_PASSWORD_FILE}")"
history_password="$(read_secret "${HISTORY_PASSWORD_FILE}")"
admin_password="$(read_secret "${ADMIN_PASSWORD_FILE}")"
redis_password="$(read_secret "${REDIS_PASSWORD_FILE}")"

export DEBIAN_FRONTEND=noninteractive
progress "installing Docker Engine and Docker Compose plugin"
apt-get update
apt-get install --yes --no-install-recommends docker.io docker-compose-v2 jq
systemctl enable --now docker
docker info >/dev/null || fail "Docker daemon is unavailable"
docker compose version >/dev/null || fail "Docker Compose plugin is unavailable"

install -d -o root -g aegis -m 0750 "${ENVIRONMENT_DIRECTORY}"

temporary_environment="$(mktemp)"
{
  printf 'MARIADB_DATABASE=aegis_history\n'
  printf 'MARIADB_USER=aegis_history\n'
  printf 'MARIADB_PASSWORD=%s\n' "${database_password}"
  printf 'MARIADB_ROOT_PASSWORD=%s\n' "${database_root_password}"
} >"${temporary_environment}"
install -o root -g root -m 0600 "${temporary_environment}" "${ENVIRONMENT_FILE}"

temporary_acl="$(mktemp)"
{
  printf 'user default off\n'
  printf 'user aegis_ui on >%s ~theme:* +get +set +del +expire +ttl +ping\n' \
    "${redis_password}"
} >"${temporary_acl}"
install -o 999 -g 999 -m 0400 "${temporary_acl}" "${REDIS_ACL_FILE}"

temporary_definitions="$(mktemp)"
jq -n \
  --arg provider_password "${provider_password}" \
  --arg history_password "${history_password}" \
  --arg admin_password "${admin_password}" \
  '{
    users: [
      {name: "aegis_provider", password: $provider_password, tags: ""},
      {name: "aegis_history", password: $history_password, tags: ""},
      {name: "aegis_admin", password: $admin_password, tags: "administrator"}
    ],
    vhosts: [{name: "/aegis"}],
    permissions: [
      {
        user: "aegis_provider", vhost: "/aegis",
        configure: "^aegis\\.blacklist$", write: "^aegis\\.blacklist$",
        read: "^$"
      },
      {
        user: "aegis_history", vhost: "/aegis",
        configure: "^(aegis\\.blacklist(\\.retry|\\.dead)?|aegis\\.history\\.blacklist\\.snapshots(\\.retry\\.(300|900|1800|3600)|\\.dead)?)$",
        write: "^(aegis\\.blacklist(\\.retry|\\.dead)?|aegis\\.history\\.blacklist\\.snapshots(\\.retry\\.(300|900|1800|3600)|\\.dead)?)$",
        read: "^(aegis\\.blacklist(\\.retry|\\.dead)?|aegis\\.history\\.blacklist\\.snapshots(\\.retry\\.(300|900|1800|3600)|\\.dead)?)$"
      },
      {
        user: "aegis_admin", vhost: "/aegis",
        configure: ".*", write: ".*", read: ".*"
      }
    ],
    exchanges: [
      {name: "aegis.blacklist", vhost: "/aegis", type: "direct", durable: true, auto_delete: false, internal: false, arguments: {}},
      {name: "aegis.blacklist.retry", vhost: "/aegis", type: "direct", durable: true, auto_delete: false, internal: false, arguments: {}},
      {name: "aegis.blacklist.dead", vhost: "/aegis", type: "direct", durable: true, auto_delete: false, internal: false, arguments: {}}
    ],
    queues: (
      [{
        name: "aegis.history.blacklist.snapshots", vhost: "/aegis",
        durable: true, auto_delete: false, arguments: {}
      }, {
        name: "aegis.history.blacklist.snapshots.dead", vhost: "/aegis",
        durable: true, auto_delete: false, arguments: {}
      }] + [
        {delay: 300}, {delay: 900}, {delay: 1800}, {delay: 3600}
      ] | map(if has("delay") then {
        name: ("aegis.history.blacklist.snapshots.retry." + (.delay | tostring)),
        vhost: "/aegis", durable: true, auto_delete: false,
        arguments: {
          "x-message-ttl": (.delay * 1000),
          "x-dead-letter-exchange": "aegis.blacklist",
          "x-dead-letter-routing-key": "blacklist.snapshot.complete"
        }
      } else . end)
    ),
    bindings: (
      [{
        source: "aegis.blacklist",
        vhost: "/aegis",
        destination: "aegis.history.blacklist.snapshots",
        destination_type: "queue",
        routing_key: "blacklist.snapshot.complete",
        arguments: {}
      }, {
        source: "aegis.blacklist.dead",
        vhost: "/aegis",
        destination: "aegis.history.blacklist.snapshots.dead",
        destination_type: "queue",
        routing_key: "blacklist.snapshot.dead",
        arguments: {}
      }] + [
        {delay: 300}, {delay: 900}, {delay: 1800}, {delay: 3600}
      ] | map(if has("delay") then {
        source: "aegis.blacklist.retry",
        vhost: "/aegis",
        destination: ("aegis.history.blacklist.snapshots.retry." + (.delay | tostring)),
        destination_type: "queue",
        routing_key: ("blacklist.snapshot.retry." + (.delay | tostring)),
        arguments: {}
      } else . end)
    )
  }' >"${temporary_definitions}"
install -o 999 -g 999 -m 0400 "${temporary_definitions}" "${DEFINITIONS_FILE}"

export AEGIS_INFRA_ENV_FILE="${ENVIRONMENT_FILE}"
export AEGIS_RABBITMQ_DEFINITIONS_FILE="${DEFINITIONS_FILE}"
export AEGIS_REDIS_ACL_FILE="${REDIS_ACL_FILE}"
progress "starting MariaDB, RabbitMQ, and Redis containers"
docker compose -f "${COMPOSE_FILE}" config --quiet
docker compose -f "${COMPOSE_FILE}" up --detach --remove-orphans

wait_for_health() {
  local container="$1"
  local attempts=90
  while (( attempts > 0 )); do
    if docker inspect --format '{{.State.Health.Status}}' "${container}" \
      2>/dev/null | grep -Fxq healthy; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done
  fail "${container} did not become healthy"
}

wait_for_health aegis-mariadb
wait_for_health aegis-rabbitmq
wait_for_health aegis-redis

docker exec aegis-rabbitmq rabbitmqctl -q list_vhosts name | \
  grep -Fxq /aegis || fail "RabbitMQ vhost was not initialized"
docker exec aegis-rabbitmq rabbitmqctl -q list_queues -p /aegis name durable | \
  awk '$1 == "aegis.history.blacklist.snapshots" && $2 == "true" {found=1}
       END {exit !found}' || fail "durable RabbitMQ queue was not initialized"

progress "MariaDB, RabbitMQ, and Redis containers are healthy on 192.168.100.14"
