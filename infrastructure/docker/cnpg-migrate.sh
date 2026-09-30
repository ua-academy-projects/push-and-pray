#!/bin/sh
set -eu

database_name="${1:?database name is required}"
database_owner="${2:?database owner is required}"

# CNPG permits local administrative access through peer authentication.
# No remote superuser password is enabled or passed to this process.
run_psql() {
    psql --host=/controller/run --username=postgres --dbname="$database_name" \
        --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

run_psql <<'SQL'
CREATE SCHEMA IF NOT EXISTS oilscope_admin;
REVOKE ALL ON SCHEMA oilscope_admin FROM PUBLIC;
CREATE TABLE IF NOT EXISTS oilscope_admin.migrations (
    name TEXT PRIMARY KEY,
    checksum TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# Use the repository's existing SQL files in order. Each file is idempotent,
# so interruption before the ledger update can safely retry that file.
for migration in /opt/petroscope/migrations/*.sql; do
    migration_name="$(basename "$migration")"
    migration_checksum="$(sha256sum "$migration" | cut -d ' ' -f 1)"
    applied_checksum="$(run_psql --tuples-only --no-align --set=migration_name="$migration_name" <<'SQL'
SELECT checksum FROM oilscope_admin.migrations WHERE name = :'migration_name';
SQL
    )"
    if [ "$applied_checksum" = "$migration_checksum" ]; then
        continue
    fi
    echo "Applying $migration_name"
    run_psql --file="$migration"
    run_psql --set=migration_name="$migration_name" --set=migration_checksum="$migration_checksum" <<'SQL'
INSERT INTO oilscope_admin.migrations (name, checksum)
VALUES (:'migration_name', :'migration_checksum')
ON CONFLICT (name) DO UPDATE SET checksum = EXCLUDED.checksum, applied_at = now();
SQL
done

# Migrations run as postgres for extension/cron setup. Application accounts
# inherit the database owner's privileges, never the postgres superuser role.
run_psql --set=database_owner="$database_owner" --set=ui_user="${database_owner}_ui" <<'SQL'
GRANT USAGE ON SCHEMA public, pgmq TO :"database_owner";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public, pgmq TO :"database_owner";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public, pgmq TO :"database_owner";
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public, pgmq TO :"database_owner";
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public, pgmq
    GRANT ALL PRIVILEGES ON TABLES TO :"database_owner";
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public, pgmq
    GRANT ALL PRIVILEGES ON SEQUENCES TO :"database_owner";

-- UI readiness reads the cleanup job, which is owned by postgres. Retain
-- pg_cron's row security and expose only that job to the UI login.
GRANT USAGE ON SCHEMA cron TO :"ui_user";
GRANT SELECT ON cron.job TO :"ui_user";
SELECT format(
    'CREATE POLICY oilscope_ui_session_cleanup_read ON cron.job FOR SELECT TO %I USING (jobname = %L AND database = current_database())',
    :'ui_user', 'delete-expired-ui-sessions'
)
WHERE NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'cron' AND tablename = 'job'
      AND policyname = 'oilscope_ui_session_cleanup_read'
)
\gexec
SQL

echo "Database migrations completed successfully"
