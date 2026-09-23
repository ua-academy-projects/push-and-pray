#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

sync_docker_project
write_compose_env

backup_dir="/var/backups/oil-price-tracker"
native_backup="${backup_dir}/native-postgres-before-docker.dump"
import_marker="/var/lib/oil-price-tracker-native-postgres-imported"
native_rows=0

if systemctl is-active --quiet postgresql 2>/dev/null && command -v psql >/dev/null 2>&1; then
  if sudo -u postgres psql -d oil_tracker -Atc \
    "SELECT to_regclass('public.price_observations')" 2>/dev/null | grep -qx price_observations; then
    log "Applying current SQL migrations to native PostgreSQL before backup"
    for migration in "${PROJECT_SHARE}"/database/migrations/*.sql; do
      PGPASSWORD="${DB_PASSWORD}" psql \
        -h 127.0.0.1 \
        -U oil_tracker \
        -d oil_tracker \
        -v ON_ERROR_STOP=1 \
        -f "${migration}"
    done

    native_rows="$(sudo -u postgres psql -d oil_tracker -Atc \
      'SELECT count(*) FROM price_observations')"
    if [[ "${native_rows}" -gt 0 && ! -f "${import_marker}" ]]; then
      install -d -o postgres -g postgres -m 0700 "${backup_dir}"
      sudo -u postgres pg_dump \
        --dbname=oil_tracker \
        --table=price_observations \
        --data-only \
        --format=custom \
        --file="${native_backup}"
      log "Backed up ${native_rows} native PostgreSQL rows before container migration"
    fi
  fi
fi

disable_native_units postgresql.service

docker_compose database up --detach --remove-orphans
wait_for_compose_health database postgres 90

for migration in "${DOCKER_PROJECT_ROOT}"/database/migrations/*.sql; do
  log "Applying container database migration: $(basename "${migration}")"
  docker_compose database exec -T postgres \
    psql -U oil_tracker -d oil_tracker -v ON_ERROR_STOP=1 \
    < "${migration}"
done

docker_compose database exec -T postgres \
  psql -U oil_tracker -d oil_tracker -v ON_ERROR_STOP=1 \
  -c "ALTER DATABASE oil_tracker SET timezone TO 'UTC';"

container_rows="$(docker_compose database exec -T postgres \
  psql -U oil_tracker -d oil_tracker -Atc 'SELECT count(*) FROM price_observations')"

if [[ -f "${native_backup}" && ! -f "${import_marker}" ]]; then
  if [[ "${container_rows}" -eq 0 ]]; then
    log "Restoring native PostgreSQL rows into the Docker volume"
    docker_compose database exec -T postgres \
      pg_restore \
        -U oil_tracker \
        -d oil_tracker \
        --data-only \
        --no-owner \
        --exit-on-error \
      < "${native_backup}"
  else
    log "Docker PostgreSQL already contains ${container_rows} rows; native restore skipped"
  fi
  touch "${import_marker}"
fi

allow_port_if_firewall_active 5432

final_rows="$(docker_compose database exec -T postgres \
  psql -U oil_tracker -d oil_tracker -Atc 'SELECT count(*) FROM price_observations')"
log "Database Compose project is ready at ${DB_LAN_IP}:5432 with ${final_rows} observations"
