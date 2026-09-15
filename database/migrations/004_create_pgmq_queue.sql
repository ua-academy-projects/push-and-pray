BEGIN;

-- The queue lives inside PostgreSQL only where the PGMQ extension exists. The
-- managed services offer none, so on those servers the fetcher and the history
-- service talk through a message broker instead and this migration has
-- nothing to create.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_available_extensions
        WHERE name = 'pgmq'
    ) THEN
        RAISE NOTICE 'pgmq is not available on this server; the queue lives in the message broker instead';
        RETURN;
    END IF;

    CREATE EXTENSION IF NOT EXISTS pgmq;

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
