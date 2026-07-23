#!/usr/bin/env bash
# Provisions the postgres VM: installs PostgreSQL, creates the skyivano and
# skyivano_test databases, and opens it up so the history-service VM can
# reach it. Safe to re-run.
#
# Networking note: there is no private LAN between the VMs (see Vagrantfile).
# The history-service VM reaches this one via its own QEMU slirp gateway
# alias (10.0.2.2) -> the real host -> this VM's forwarded port 5432. Once
# that connection lands inside this guest, its source address is the slirp
# gateway itself (10.0.2.2) - that's what pg_hba.conf must allow, not a LAN
# subnet or 127.0.0.1.
set -euo pipefail

DB_USER="skyivano"
DB_PASS="skyivano"
DB_NAME="skyivano"
DB_TEST_NAME="skyivano_test"
GATEWAY="10.0.2.2"

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

echo ">>> Opening PostgreSQL to the history-service VM (via ${GATEWAY})"
PG_CONF="$(sudo -u postgres psql -tAc 'SHOW config_file')"
PG_HBA="$(sudo -u postgres psql -tAc 'SHOW hba_file')"

sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"

if ! grep -q "${GATEWAY}/32" "$PG_HBA"; then
  echo "host    all             all             ${GATEWAY}/32            md5" >> "$PG_HBA"
fi

systemctl restart postgresql

echo ">>> Provisioning complete"
echo "    Postgres reachable at localhost:5432 on the host, or ${GATEWAY}:5432 from other VMs (user=${DB_USER} db=${DB_NAME}/${DB_TEST_NAME})"
