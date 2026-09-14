\set ON_ERROR_STOP on
\getenv runtime_user RUNTIME_DB_USER
\getenv runtime_role RUNTIME_DB_ROLE
BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'runtime_user')
\gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'runtime_user')
\gexec
-- Reconcile grants on existing tables without granting DDL or ownership.
SELECT format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', :'runtime_user')
\gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO %I', table_name, :'runtime_user')
FROM (VALUES ('fetcher', 'published_queue_events'),
             ('history', 'price_observations')) AS access(service_role, table_name)
WHERE service_role = :'runtime_role'
\gexec
-- Future admin-created objects must not implicitly expose privileges to PUBLIC.
-- New tables need an explicit runtime grant above as part of their migration.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;
COMMIT;
