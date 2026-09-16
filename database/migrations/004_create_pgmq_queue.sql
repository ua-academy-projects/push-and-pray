BEGIN;

CREATE EXTENSION IF NOT EXISTS pgmq;

\if :{?pgmq_queue}
\else
\set pgmq_queue price_observations
\endif

SELECT pgmq.create(:'pgmq_queue')
WHERE NOT EXISTS (
    SELECT 1
    FROM pgmq.list_queues()
    WHERE queue_name = :'pgmq_queue'
);

COMMIT;
