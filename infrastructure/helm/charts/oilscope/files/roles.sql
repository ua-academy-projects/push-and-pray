\set ON_ERROR_STOP on
\getenv runtime_user RUNTIME_DB_USER
\getenv runtime_password RUNTIME_DB_PASSWORD
BEGIN;
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT', :'runtime_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'runtime_user')
\gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'runtime_user', :'runtime_password')
\gexec
COMMIT;
