import type { SyncHistoryStatus } from "../hooks/useSyncHistory";
import type { SyncLogEntry } from "../types/sync";
import { formatTime } from "../utils/dateFormat";
import styles from "./SyncLogPanel.module.css";

interface SyncLogPanelProps {
  entries: SyncLogEntry[] | null;
  status: SyncHistoryStatus;
}

const TRIGGER_LABELS: Record<SyncLogEntry["trigger_type"], string> = {
  scheduler: "scheduled",
  startup: "startup",
  internal_endpoint: "manual",
};

/** The inline accordion contents beneath StatusStrip -- recent synchronization attempts,
 * newest first. A genuinely different feature from the stale-data banner: this is a log a
 * user actively opens, not a passive warning. */
export function SyncLogPanel({ entries, status }: SyncLogPanelProps) {
  if (status === "loading" || status === "idle") {
    return <p className={styles.empty}>Loading sync history…</p>;
  }

  if (status === "error") {
    return <p className={styles.empty}>Couldn't load sync history.</p>;
  }

  if (!entries || entries.length === 0) {
    return <p className={styles.empty}>No synchronization attempts recorded yet.</p>;
  }

  return (
    <ol className={styles.list} aria-label="Synchronization history">
      {entries.map((entry) => {
        const ok = entry.status === "success";
        return (
          <li key={entry.id} className={styles.row}>
            <span className={styles.time}>{formatTime(entry.started_at)}</span>
            <span className={`${styles.statusChip} ${ok ? styles.ok : styles.failed}`}>
              <span aria-hidden="true">{ok ? "✓" : "✕"}</span>
              {ok ? "Success" : "Failed"}
            </span>
            <span className={styles.note}>
              {entry.error_message ??
                (entry.daily_records_received !== null
                  ? `${entry.daily_records_received} daily · ${entry.forecast_records_received ?? 0} forecast · ${entry.hourly_records_received ?? 0} hourly`
                  : "—")}
            </span>
            <span className={styles.trigger}>{TRIGGER_LABELS[entry.trigger_type]}</span>
          </li>
        );
      })}
    </ol>
  );
}
