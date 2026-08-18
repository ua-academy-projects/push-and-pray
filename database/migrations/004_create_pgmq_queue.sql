BEGIN;

CREATE EXTENSION IF NOT EXISTS pgmq;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pgmq.list_queues()
        WHERE queue_name = 'price_observations'
    ) THEN
        PERFORM pgmq.create('price_observations');
    END IF;
END
$$;

COMMIT;