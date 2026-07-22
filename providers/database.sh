#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

readonly DATABASE_NAME="weather_history"
readonly DATABASE_USER="weather_user"
readonly BACKEND_IP="192.168.56.11"
readonly DATABASE_IP="192.168.56.13"

log "Installing PostgreSQL"
install_packages \
    postgresql \
    postgresql-contrib

systemctl enable --now postgresql

log "Creating the PostgreSQL role and database"

sudo -u postgres psql <<'SQL'
DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles
        WHERE rolname = 'weather_user'
    ) THEN
        CREATE ROLE weather_user
        LOGIN
        PASSWORD 'weather_password';
    ELSE
        ALTER ROLE weather_user
        PASSWORD 'weather_password';
    END IF;
END
$$;

SELECT 'CREATE DATABASE weather_history OWNER weather_user'
WHERE NOT EXISTS (
    SELECT FROM pg_database
    WHERE datname = 'weather_history'
)\gexec

GRANT ALL PRIVILEGES
ON DATABASE weather_history
TO weather_user;
SQL

postgres_version="$(
    find /etc/postgresql \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' \
        | sort -V \
        | tail -n 1
)"

postgresql_conf="/etc/postgresql/${postgres_version}/main/postgresql.conf"
pg_hba_conf="/etc/postgresql/${postgres_version}/main/pg_hba.conf"

log "Restricting PostgreSQL to the backend private address"

sed -i -E \
    "s/^[#[:space:]]*listen_addresses[[:space:]]*=.*/listen_addresses = 'localhost,${DATABASE_IP}'/" \
    "${postgresql_conf}"

sed -i \
    '\|host weather_history weather_user 192.168.56.0/24 scram-sha-256|d' \
    "${pg_hba_conf}"

backend_rule="host ${DATABASE_NAME} ${DATABASE_USER} ${BACKEND_IP}/32 scram-sha-256"

if ! grep -Fqx \
    "${backend_rule}" \
    "${pg_hba_conf}"; then

    printf '%s\n' \
        "${backend_rule}" \
        >> "${pg_hba_conf}"
fi

systemctl restart postgresql

log "PostgreSQL provisioning completed"
