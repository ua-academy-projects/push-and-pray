#!/usr/bin/env bash
# Provisions the postgres VM: installs PostgreSQL, creates the skyivano and
# skyivano_test databases, and opens it up so the backend-service VM can
# reach it. Also installs Redis on this same VM (session storage for the
# UI - see docs/architecture.md), since it shares this VM's role as the
# project's one "data/infra" node rather than an application node. Safe to
# re-run.
#
# Networking note: all VMs are bridged onto the host's LAN (see
# Vagrantfile), each with its own fixed IP - no NAT/slirp gateway trick
# needed. Only the backend-service VM talks to Postgres or Redis directly,
# so pg_hba.conf and Redis's bind address are both scoped to that VM's
# specific bridged IP, not the whole LAN.
set -euo pipefail

DB_USER="skyivano"
DB_PASS="skyivano"
DB_NAME="skyivano"
DB_TEST_NAME="skyivano_test"
BACKEND_IP="192.168.0.221"
OWN_IP="192.168.0.220"

export DEBIAN_FRONTEND=noninteractive

# `sudo -u postgres` inherits this script's cwd, which the postgres user
# can't enter (this VM's provisioner script runs from /home/vagrant); run
# from /tmp instead so `sudo -u postgres psql ...` below doesn't warn.
cd /tmp

echo ">>> Installing PostgreSQL"
apt-get update -y
apt-get install -y postgresql postgresql-contrib

echo ">>> Creating role and databases"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
  || sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_TEST_NAME}'" | grep -q 1 \
  || sudo -u postgres createdb -O "${DB_USER}" "${DB_TEST_NAME}"

echo ">>> Opening PostgreSQL to the backend-service VM (${BACKEND_IP})"
PG_CONF="$(sudo -u postgres psql -tAc 'SHOW config_file')"
PG_HBA="$(sudo -u postgres psql -tAc 'SHOW hba_file')"

sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"

if ! grep -q "${BACKEND_IP}/32" "$PG_HBA"; then
  echo "host    all             all             ${BACKEND_IP}/32            md5" >> "$PG_HBA"
fi

systemctl restart postgresql

echo ">>> Installing Redis"
apt-get install -y redis-server

echo ">>> Binding Redis to this VM's own LAN IP (${OWN_IP}) so the backend-service VM can reach it"
# No auth configured -- matches this project's existing v1 stance on internal-only services
# (see docs/architecture.md §11/§12); Redis here only ever stores ephemeral UI session state,
# never business data, and is only reachable from inside the bridged LAN.
REDIS_CONF="/etc/redis/redis.conf"
sed -i "s/^bind .*/bind 127.0.0.1 ${OWN_IP}/" "$REDIS_CONF"
sed -i "s/^protected-mode .*/protected-mode no/" "$REDIS_CONF"
systemctl restart redis-server

echo ">>> Provisioning complete"
echo "    Postgres reachable at 192.168.0.220:5432 on the LAN (user=${DB_USER} db=${DB_NAME}/${DB_TEST_NAME})"
echo "    Redis reachable at 192.168.0.220:6379 on the LAN (UI session state only)"
