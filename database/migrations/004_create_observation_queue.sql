BEGIN;

-- Plain-SQL replacement for the pgmq "price_observations" queue. Works on any
-- PostgreSQL, managed Cloud SQL / RDS included, with no extension: consumers
-- claim rows with SELECT ... FOR UPDATE SKIP LOCKED, so concurrent readers
-- never take the same message. A row is available once its visibility time
-- (vt) is in the past; reading pushes vt forward and bumps read_ct, which is
-- how redelivery and the poison-message limit work.
CREATE TABLE IF NOT EXISTS observation_queue (
    msg_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message     JSONB       NOT NULL,
    read_ct     INTEGER     NOT NULL DEFAULT 0,
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    vt          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Consumers scan visible rows (vt <= now()) oldest-first.
CREATE INDEX IF NOT EXISTS ix_observation_queue_vt
    ON observation_queue (vt, msg_id);

-- Archived messages (successfully persisted, or dead-lettered after the read
-- limit) are kept here, mirroring pgmq.archive rather than dropping them.
CREATE TABLE IF NOT EXISTS observation_queue_archive (
    msg_id      BIGINT PRIMARY KEY,
    message     JSONB       NOT NULL,
    read_ct     INTEGER     NOT NULL,
    enqueued_at TIMESTAMPTZ NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;
