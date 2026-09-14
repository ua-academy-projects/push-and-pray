#!/bin/sh
set -eu

: "${MIGRATION_PROFILE:=application}"
case "${MIGRATION_PROFILE}" in
    application|cloud) ;;
    *)
        echo "MIGRATION_PROFILE must be application or cloud" >&2
        exit 1
        ;;
esac

migrations_root=/opt/petroscope/migrations
for directory in "${migrations_root}/common" "${migrations_root}/${MIGRATION_PROFILE}"; do
    if [ ! -d "${directory}" ]; then
        echo "Missing migration directory: ${directory}" >&2
        exit 1
    fi
done

# Common migrations and the application profile must never be silently skipped.
set -- "${migrations_root}/common/"*.sql
if [ ! -f "$1" ]; then
    echo "No common migrations found" >&2
    exit 1
fi
if [ "${MIGRATION_PROFILE}" = application ]; then
    set -- "${migrations_root}/application/"*.sql
    if [ ! -f "$1" ]; then
        echo "No application migrations found" >&2
        exit 1
    fi
fi

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

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

for migration in "${migrations_root}/common/"*.sql \
    "${migrations_root}/${MIGRATION_PROFILE}/"*.sql; do
    # The cloud profile currently has no SQL files; ignore its unmatched glob.
    [ -f "${migration}" ] || continue
    echo "Applying $(basename "${migration}")"

    psql \
        --host="${PGHOST}" \
        --port="${PGPORT}" \
        --username="${PGUSER}" \
        --dbname="${PGDATABASE}" \
        --set=ON_ERROR_STOP=1 \
        --file="${migration}"
done

echo "Database migrations completed successfully"
