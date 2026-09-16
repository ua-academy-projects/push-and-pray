#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${MIGRATION_PROFILE:=self_managed}"

case "${MIGRATION_PROFILE}" in
    managed|self_managed) ;;
    *)
        echo "MIGRATION_PROFILE must be managed or self_managed" >&2
        exit 1
        ;;
esac

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

for migration in /opt/petroscope/migrations/*.sql; do
    migration_name="$(basename "${migration}")"

    if [ "${MIGRATION_PROFILE}" = "managed" ]; then
        case "${migration_name}" in
            001_*|002_*) ;;
            *) continue ;;
        esac
    fi

    echo "Applying ${migration_name}"

    psql \
        --host="${PGHOST}" \
        --port="${PGPORT}" \
        --username="${PGUSER}" \
        --dbname="${PGDATABASE}" \
        --set=ON_ERROR_STOP=1 \
        --set="pgmq_queue=${PGMQ_QUEUE:-price_observations}" \
        --file="${migration}"
done

echo "Database migrations completed successfully"
