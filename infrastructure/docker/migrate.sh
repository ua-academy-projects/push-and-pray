#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${DATABASE_MODE:=self_managed}"

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
    case "${DATABASE_MODE}:$(basename "${migration}")" in
        managed:003_*|managed:004_*|managed:005_*)
            echo "Skipping self-managed migration $(basename "${migration}")"
            continue
            ;;
    esac

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
