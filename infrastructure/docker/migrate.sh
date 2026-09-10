#!/bin/sh
set -eu

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

MIGRATION_SKIP="${MIGRATION_SKIP:-}"

for migration in /opt/petroscope/migrations/*.sql; do
    base="$(basename "${migration}")"

    case " ${MIGRATION_SKIP} " in
        *" ${base} "*)
            echo "Skipping ${base}"
            continue
            ;;
    esac

    echo "Applying ${base}"

    psql \
        --host="${PGHOST}" \
        --port="${PGPORT}" \
        --username="${PGUSER}" \
        --dbname="${PGDATABASE}" \
        --set=ON_ERROR_STOP=1 \
        --file="${migration}"
done
echo "Database migrations completed successfully"
