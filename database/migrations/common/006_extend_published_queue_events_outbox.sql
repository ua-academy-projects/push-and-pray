BEGIN;

ALTER TABLE published_queue_events
    ADD COLUMN IF NOT EXISTS payload JSONB,
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'sent'
        CHECK (status IN ('pending', 'sent')),
    ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_published_queue_events_pending_has_payload'
          AND conrelid = 'published_queue_events'::regclass
    ) THEN
        ALTER TABLE published_queue_events
            ADD CONSTRAINT ck_published_queue_events_pending_has_payload
            CHECK (status <> 'pending' OR payload IS NOT NULL);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ix_published_queue_events_pending
    ON published_queue_events (next_attempt_at)
    WHERE status = 'pending';

COMMIT;
