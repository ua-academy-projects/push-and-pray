/** GET /api/sync-status. `next_scheduled_at` is always null as of Stage 2/3 -- the Backend has
 * no visibility into the Fetcher's autonomous scheduler without violating "Backend calls
 * Fetcher in exactly one case" (see docs/architecture.md §4), so the UI never renders it. */
export interface SyncStatusResponse {
  synchronization_status: string | null;
  last_synchronized_at: string | null;
  last_attempted_at: string | null;
  next_scheduled_at: string | null;
  sync_in_progress: boolean;
  is_stale: boolean;
  stale_reason: string | null;
}

/** One row of GET /api/sync/history. */
export interface SyncLogEntry {
  id: number;
  location_id: number;
  started_at: string;
  completed_at: string | null;
  status: "in_progress" | "success" | "failed" | "skipped";
  source: string;
  trigger_type: "startup" | "scheduler" | "internal_endpoint";
  open_meteo_request_url: string | null;
  open_meteo_status_code: number | null;
  open_meteo_duration_ms: number | null;
  records_received: number | null;
  daily_records_received: number | null;
  forecast_records_received: number | null;
  hourly_records_received: number | null;
  error_message: string | null;
  created_at: string;
}
