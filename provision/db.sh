#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y postgresql postgresql-contrib

PG_VERSION=$(ls /etc/postgresql)
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"

if ! grep -q "192.168.56.0/24" "$PG_HBA"; then
  echo "host all all 192.168.56.0/24 md5" >> "$PG_HBA"
fi

systemctl restart postgresql

cd /tmp
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE \"${DB_NAME}\" OWNER ${DB_USER};"
