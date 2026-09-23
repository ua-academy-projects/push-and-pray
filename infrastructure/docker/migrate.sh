#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

export PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD

attempt=1
max_attempts=30

until pg_isready
do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "PostgreSQL did not become ready" >&2
        exit 1
    fi

    attempt=$((attempt + 1))
    sleep 2
done

psql --set=ON_ERROR_STOP=1 -q -c \
    "CREATE TABLE IF NOT EXISTS schema_migrations (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"

MIGRATION_SKIP="${MIGRATION_SKIP:-}"

for migration in /opt/petroscope/migrations/*.sql; do
    base="$(basename "${migration}")"

    case " ${MIGRATION_SKIP} " in
        *" ${base} "*)
            echo "Skipping ${base}"
            continue
            ;;
    esac

    if [ "$(psql --set=ON_ERROR_STOP=1 -tAc "SELECT 1 FROM schema_migrations WHERE filename = '${base}'")" = "1" ]; then
        echo "Already applied ${base}"
        continue
    fi

    echo "Applying ${base}"

    psql --single-transaction --set=ON_ERROR_STOP=1 \
        --file="${migration}" \
        -c "INSERT INTO schema_migrations (filename) VALUES ('${base}');"
done

echo "Database migrations completed successfully"
