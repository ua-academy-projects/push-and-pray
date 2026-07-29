#!/usr/bin/env bash

set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

required_variables=(
    AIRAWARE_DATABASE_IP
    AIRAWARE_BACKEND_IP
    AIRAWARE_DB_NAME
    AIRAWARE_DB_USER
    AIRAWARE_DB_PASSWORD
    AIRAWARE_REDIS_PASSWORD
    AIRAWARE_FETCHER_IP
    AIRAWARE_RABBITMQ_USER
    AIRAWARE_RABBITMQ_PASSWORD
    AIRAWARE_RABBITMQ_VHOST
)

for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required variable is missing: ${variable_name}" >&2
        exit 1
    fi
done

SCHEMA_FILE="/vagrant/backend-service/database/init.sql"

if [[ ! -f "${SCHEMA_FILE}" ]]; then
    echo "Database schema file is missing: ${SCHEMA_FILE}" >&2
    exit 1
fi

log "Installing PostgreSQL"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    postgresql \
    postgresql-client \
    postgresql-contrib \
    redis-server \
    redis-tools \
    rabbitmq-server \
    ufw

PG_VERSION="$(
    find /etc/postgresql \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
    sort -V |
    tail -n 1
)"

if [[ -z "${PG_VERSION}" ]]; then
    echo "Could not determine the installed PostgreSQL version" >&2
    exit 1
fi

POSTGRESQL_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA_CONF="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

log "Using PostgreSQL version ${PG_VERSION}"

# Listen only on loopback and the VM's bridged LAN address.
if grep -Eq '^[#[:space:]]*listen_addresses[[:space:]]*=' \
    "${POSTGRESQL_CONF}"; then

    sed -Ei \
        "s|^[#[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = 'localhost,${AIRAWARE_DATABASE_IP}'|" \
        "${POSTGRESQL_CONF}"
else
    printf "\nlisten_addresses = 'localhost,%s'\n" \
        "${AIRAWARE_DATABASE_IP}" \
        >>"${POSTGRESQL_CONF}"
fi

# Replace our managed pg_hba section when reprovisioning.
sed -i \
    '/# BEGIN AIRAWARE ACCESS/,/# END AIRAWARE ACCESS/d' \
    "${PG_HBA_CONF}"

cat >>"${PG_HBA_CONF}" <<EOF

# BEGIN AIRAWARE ACCESS
host    ${AIRAWARE_DB_NAME}    ${AIRAWARE_DB_USER}    ${AIRAWARE_BACKEND_IP}/32    scram-sha-256
# END AIRAWARE ACCESS
EOF

systemctl enable postgresql
systemctl restart postgresql

escaped_password="$(
    printf '%s' "${AIRAWARE_DB_PASSWORD}" |
    sed "s/'/''/g"
)"

log "Creating or updating the application database role"

if sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${AIRAWARE_DB_USER}'" |
    grep -q 1; then

    sudo -u postgres psql \
        -v ON_ERROR_STOP=1 \
        -c "ALTER ROLE ${AIRAWARE_DB_USER} WITH LOGIN PASSWORD '${escaped_password}';"
else
    sudo -u postgres psql \
        -v ON_ERROR_STOP=1 \
        -c "CREATE ROLE ${AIRAWARE_DB_USER} WITH LOGIN PASSWORD '${escaped_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;"
fi

log "Creating the application database"

if ! sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${AIRAWARE_DB_NAME}'" |
    grep -q 1; then

    sudo -u postgres createdb \
        --owner="${AIRAWARE_DB_USER}" \
        "${AIRAWARE_DB_NAME}"
fi

log "Executing the database initialization script"

PGPASSWORD="${AIRAWARE_DB_PASSWORD}" \
psql \
    --host=127.0.0.1 \
    --username="${AIRAWARE_DB_USER}" \
    --dbname="${AIRAWARE_DB_NAME}" \
    --set=ON_ERROR_STOP=1 \
    --file="${SCHEMA_FILE}"

log "Verifying database objects"

PGPASSWORD="${AIRAWARE_DB_PASSWORD}" \
psql \
    --host=127.0.0.1 \
    --username="${AIRAWARE_DB_USER}" \
    --dbname="${AIRAWARE_DB_NAME}" \
    --set=ON_ERROR_STOP=1 \
    --command="
        SELECT COUNT(*) AS city_count
        FROM cities;

        SELECT to_regclass(
            'public.air_quality_measurements'
        ) AS measurements_table;
    "

log "PostgreSQL listening sockets"
ss -lntp | grep ':5432' || true

REDIS_CONF="/etc/redis/redis.conf"

sed -Ei \
    "s|^[#[:space:]]*bind .*|bind 127.0.0.1 ${AIRAWARE_DATABASE_IP}|" \
    "${REDIS_CONF}"

sed -Ei \
    "s|^[#[:space:]]*protected-mode .*|protected-mode yes|" \
    "${REDIS_CONF}"

escaped_redis_password="$(
    printf '%s' "${AIRAWARE_REDIS_PASSWORD}" |
    sed 's/[&/]/\\&/g'
)"

if grep -Eq '^[#[:space:]]*requirepass ' "${REDIS_CONF}"; then
    sed -Ei \
        "s|^[#[:space:]]*requirepass .*|requirepass ${escaped_redis_password}|" \
        "${REDIS_CONF}"
else
    printf '\nrequirepass %s\n' \
        "${escaped_redis_password}" \
        >>"${REDIS_CONF}"
fi

systemctl enable redis-server
systemctl restart redis-server

redis-cli \
    -h 127.0.0.1 \
    -a "${AIRAWARE_REDIS_PASSWORD}" \
    --no-auth-warning \
    ping

log "Configuring RabbitMQ"

RABBITMQ_CONF="/etc/rabbitmq/rabbitmq.conf"

cat >"${RABBITMQ_CONF}" <<EOF
listeners.tcp.1 = 127.0.0.1:5672
listeners.tcp.2 = ${AIRAWARE_DATABASE_IP}:5672
management.tcp.ip = ${AIRAWARE_DATABASE_IP}
management.tcp.port = 15672
loopback_users.guest = true
EOF

systemctl enable rabbitmq-server
systemctl restart rabbitmq-server
rabbitmq-plugins enable rabbitmq_management
systemctl restart rabbitmq-server

if rabbitmqctl list_vhosts -q | grep -Fxq "${AIRAWARE_RABBITMQ_VHOST}"; then
    log "RabbitMQ vhost already exists"
else
    rabbitmqctl add_vhost "${AIRAWARE_RABBITMQ_VHOST}"
fi

if rabbitmqctl list_users -q | awk '{print $1}' | grep -Fxq "${AIRAWARE_RABBITMQ_USER}"; then
    rabbitmqctl change_password \
        "${AIRAWARE_RABBITMQ_USER}" \
        "${AIRAWARE_RABBITMQ_PASSWORD}"
else
    rabbitmqctl add_user \
        "${AIRAWARE_RABBITMQ_USER}" \
        "${AIRAWARE_RABBITMQ_PASSWORD}"
fi

rabbitmqctl set_permissions \
    -p "${AIRAWARE_RABBITMQ_VHOST}" \
    "${AIRAWARE_RABBITMQ_USER}" \
    '.*' '.*' '.*'

rabbitmqctl set_user_tags \
    "${AIRAWARE_RABBITMQ_USER}" \
    management

rabbitmq-diagnostics -q ping
rabbitmq-diagnostics -q listeners

ufw allow from "${AIRAWARE_BACKEND_IP}" to any port 5432 proto tcp
ufw allow from "${AIRAWARE_FRONTEND_IP}" to any port 6379 proto tcp
ufw allow from "${AIRAWARE_BACKEND_IP}" to any port 5672 proto tcp
ufw allow from "${AIRAWARE_FETCHER_IP}" to any port 5672 proto tcp

log "Infrastructure provisioning completed"
