\set ON_ERROR_STOP on
\getenv runtime_role RUNTIME_DB_ROLE
SELECT format('SELECT 1 FROM public.%I LIMIT 0', table_name)
FROM (VALUES ('fetcher', 'published_queue_events'),
             ('history', 'price_observations')) AS access(service_role, table_name)
WHERE service_role = :'runtime_role'
\gexec
-- Abort if the runtime login has administrative attributes.
SELECT 1 / ((NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)::integer)
FROM pg_roles WHERE rolname = current_user;
