-- Older backfill versions assigned the import time to requested_at for every
-- historical point. Identify true backfill request groups by their wide source
-- time span and restore the historical timestamp used for chart bucketing.
WITH backfill_requests AS (
    SELECT request_id
    FROM observations
    GROUP BY request_id
    HAVING max(source_timestamp) - min(source_timestamp) > INTERVAL '1 day'
)
DELETE FROM observations AS imported
USING backfill_requests AS backfill
WHERE imported.request_id = backfill.request_id
  AND imported.requested_at <> imported.source_timestamp
  AND EXISTS (
      SELECT 1
      FROM observations AS existing
      WHERE existing.id <> imported.id
        AND existing.source = imported.source
        AND existing.instrument_id = imported.instrument_id
        AND existing.source_timestamp = imported.source_timestamp
        AND existing.requested_at = imported.source_timestamp
  );

WITH backfill_requests AS (
    SELECT request_id
    FROM observations
    GROUP BY request_id
    HAVING max(source_timestamp) - min(source_timestamp) > INTERVAL '1 day'
)
UPDATE observations AS imported
SET requested_at = imported.source_timestamp
FROM backfill_requests AS backfill
WHERE imported.request_id = backfill.request_id
  AND imported.requested_at <> imported.source_timestamp;
