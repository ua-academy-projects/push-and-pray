#!/usr/bin/env bash
set -euo pipefail

readonly PROVIDER_PASSWORD_FILE="/tmp/aegis-rabbitmq-provider-password"
readonly HISTORY_PASSWORD_FILE="/tmp/aegis-rabbitmq-history-password"
readonly ADMIN_PASSWORD_FILE="/tmp/aegis-rabbitmq-admin-password"
readonly RABBITMQ_CONFIG="/etc/rabbitmq/rabbitmq.conf"
readonly REDIS_CONFIG="/etc/redis/redis.conf"
readonly VHOST="/aegis"
readonly PROVIDER_USER="aegis_provider"
readonly HISTORY_USER="aegis_history"
readonly ADMIN_USER="aegis_admin"

fail() {
  echo "Aegis infrastructure provisioning failed: $*" >&2
  exit 1
}

for secret_file in \
  "${PROVIDER_PASSWORD_FILE}" \
  "${HISTORY_PASSWORD_FILE}" \
  "${ADMIN_PASSWORD_FILE}"; do
  [[ -f "${secret_file}" ]] || fail "missing RabbitMQ credential upload: ${secret_file}"
done
trap 'rm -f "${PROVIDER_PASSWORD_FILE}" "${HISTORY_PASSWORD_FILE}" "${ADMIN_PASSWORD_FILE}"' EXIT

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

provider_password="$(read_secret "${PROVIDER_PASSWORD_FILE}")"
history_password="$(read_secret "${HISTORY_PASSWORD_FILE}")"
admin_password="$(read_secret "${ADMIN_PASSWORD_FILE}")"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends rabbitmq-server redis-server

rabbitmq-plugins enable --offline rabbitmq_management

temporary_config="$(mktemp)"
trap 'rm -f "${temporary_config}" "${PROVIDER_PASSWORD_FILE}" "${HISTORY_PASSWORD_FILE}" "${ADMIN_PASSWORD_FILE}"' EXIT
cat >"${temporary_config}" <<'EOF'
listeners.tcp.default = 5672
management.tcp.port = 15672
loopback_users.guest = true
EOF
if ! cmp --silent "${temporary_config}" "${RABBITMQ_CONFIG}" 2>/dev/null; then
  install -o rabbitmq -g rabbitmq -m 0640 "${temporary_config}" "${RABBITMQ_CONFIG}"
  systemctl restart rabbitmq-server
fi

systemctl enable --now rabbitmq-server
rabbitmqctl await_startup
rabbitmq-diagnostics -q ping
rabbitmq-diagnostics -q check_running

if ! rabbitmqctl -q list_vhosts name | grep -Fxq "${VHOST}"; then
  rabbitmqctl add_vhost "${VHOST}"
fi

ensure_user() {
  local username="$1"
  local password="$2"
  if rabbitmqctl -q list_users | awk '{print $1}' | grep -Fxq "${username}"; then
    rabbitmqctl change_password "${username}" "${password}" >/dev/null
  else
    rabbitmqctl add_user "${username}" "${password}" >/dev/null
  fi
}

ensure_user "${PROVIDER_USER}" "${provider_password}"
ensure_user "${HISTORY_USER}" "${history_password}"
ensure_user "${ADMIN_USER}" "${admin_password}"
rabbitmqctl set_user_tags "${PROVIDER_USER}"
rabbitmqctl set_user_tags "${HISTORY_USER}"
rabbitmqctl set_user_tags "${ADMIN_USER}" administrator

# Provider declares and publishes only the main exchange. History owns all
# queues, bindings, retry exchanges, and dead-letter topology in this namespace.
readonly MAIN_EXCHANGE='^aegis\.blacklist$'
readonly HISTORY_TOPOLOGY='^(aegis\.blacklist(\.retry|\.dead)?|aegis\.history\.blacklist\.snapshots(\.retry\.(300|900|1800|3600)|\.dead)?)$'
rabbitmqctl set_permissions -p "${VHOST}" "${PROVIDER_USER}" \
  "${MAIN_EXCHANGE}" "${MAIN_EXCHANGE}" '^$'
rabbitmqctl set_permissions -p "${VHOST}" "${HISTORY_USER}" \
  "${HISTORY_TOPOLOGY}" "${HISTORY_TOPOLOGY}" "${HISTORY_TOPOLOGY}"
rabbitmqctl set_permissions -p "${VHOST}" "${ADMIN_USER}" '.*' '.*' '.*'

# The built-in guest account remains loopback-only and is never configured in
# an application environment.
rabbitmq-diagnostics -q check_port_connectivity
rabbitmq-plugins list -e -m | grep -Fxq rabbitmq_management || \
  fail "RabbitMQ management plugin is not enabled"

temporary_redis_config="$(mktemp)"
trap 'rm -f "${temporary_config}" "${temporary_redis_config}" "${PROVIDER_PASSWORD_FILE}" "${HISTORY_PASSWORD_FILE}" "${ADMIN_PASSWORD_FILE}"' EXIT
cat >"${temporary_redis_config}" <<'EOF'
# Aegis development Redis: UI-only, private, bounded, and non-authoritative.
bind 127.0.0.1 192.168.100.14
protected-mode yes
port 6379
tcp-backlog 128
timeout 0
tcp-keepalive 300
supervised systemd
daemonize no
loglevel notice
logfile ""
databases 1

# Theme state is disposable, but periodic RDB snapshots make ordinary VM and
# service restarts less surprising without AOF write amplification.
save 900 1
save 300 10
stop-writes-on-bgsave-error no
rdbcompression yes
dbfilename dump.rdb
dir /var/lib/redis
appendonly no

maxmemory 128mb
maxmemory-policy allkeys-lru

# The UI needs only GET, SET, EXPIRE, DEL, and PING. These administrative or
# bulk-destructive commands are unavailable over the development endpoint.
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
rename-command SHUTDOWN ""
EOF
if ! cmp --silent "${temporary_redis_config}" "${REDIS_CONFIG}" 2>/dev/null; then
  install -o redis -g redis -m 0640 "${temporary_redis_config}" "${REDIS_CONFIG}"
  systemctl restart redis-server
fi
systemctl enable --now redis-server

redis_attempts=30
until redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -Fxq PONG; do
  redis_attempts=$((redis_attempts - 1))
  (( redis_attempts > 0 )) || fail "Redis did not become ready"
  sleep 2
done

echo "RabbitMQ is ready on 192.168.100.14:5672 (vhost ${VHOST})"
echo "Management UI is forwarded to http://127.0.0.1:15672"
echo "Redis is ready for ui-vm only on 192.168.100.14:6379"
