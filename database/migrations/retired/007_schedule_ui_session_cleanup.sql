BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'delete-expired-ui-sessions',
    '* * * * *',
    $$DELETE FROM public.ui_sessions WHERE expires_at <= CURRENT_TIMESTAMP$$
);

COMMIT;
