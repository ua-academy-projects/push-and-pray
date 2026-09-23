#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGSSLMODE:=prefer}"

attempt=1
max_attempts=30

until pg_isready \
    --host="${PGHOST}" \
    --port="${PGPORT}" \
    --username="${PGUSER}" \
    --dbname="${PGDATABASE}"
do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "PostgreSQL did not become ready" >&2
        exit 1
    fi

    attempt=$((attempt + 1))
    sleep 2
done

psql \
    --host="${PGHOST}" \
    --port="${PGPORT}" \
    --username="${PGUSER}" \
    --dbname="${PGDATABASE}" \
    --set=ON_ERROR_STOP=1 \
    --command='CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );'

applied_count=0

for migration in /opt/petroscope/migrations/*.sql; do
    version="$(basename "${migration}")"
    checksum="$(sha256sum "${migration}" | awk '{print $1}')"
    recorded_checksum="$(
        psql \
            --host="${PGHOST}" \
            --port="${PGPORT}" \
            --username="${PGUSER}" \
            --dbname="${PGDATABASE}" \
            --set=ON_ERROR_STOP=1 \
            --set="migration_version=${version}" \
            --tuples-only \
            --no-align \
            --command="SELECT checksum FROM schema_migrations
                       WHERE version = :'migration_version';"
    )"

    if [ -n "${recorded_checksum}" ]; then
        if [ "${recorded_checksum}" != "${checksum}" ]; then
            echo "Migration ${version} was modified after being applied" >&2
            exit 1
        fi

        echo "Skipping ${version}; already applied"
        continue
    fi

    echo "Applying ${version}"

    psql \
        --host="${PGHOST}" \
        --port="${PGPORT}" \
        --username="${PGUSER}" \
        --dbname="${PGDATABASE}" \
        --set=ON_ERROR_STOP=1 \
        --file="${migration}"

    psql \
        --host="${PGHOST}" \
        --port="${PGPORT}" \
        --username="${PGUSER}" \
        --dbname="${PGDATABASE}" \
        --set=ON_ERROR_STOP=1 \
        --set="migration_version=${version}" \
        --set="migration_checksum=${checksum}" \
        --command="INSERT INTO schema_migrations (version, checksum)
                   VALUES (:'migration_version', :'migration_checksum');"

    applied_count=$((applied_count + 1))
done

echo "Database migrations completed successfully; applied=${applied_count}"
