import { useState } from "react";
import { useSyncHistory } from "../hooks/useSyncHistory";
import { useSyncStatus } from "../hooks/useSyncStatus";
import { useSyncTrigger } from "../hooks/useSyncTrigger";
import { relativeTimeFromNow } from "../utils/dateFormat";
import { SyncLogPanel } from "./SyncLogPanel";
import styles from "./StatusStrip.module.css";

interface StatusStripProps {
  /** Called after a manual refresh completes successfully, so the parent can re-pull the
   * main weather data. StatusStrip owns its own sync-status/sync-history state either way. */
  onSyncSuccess?: () => void;
}

export function StatusStrip({ onSyncSuccess }: StatusStripProps) {
  const [logOpen, setLogOpen] = useState(false);
  const syncStatus = useSyncStatus();
  const syncHistory = useSyncHistory();

  // `onSettled` fires after every attempt regardless of outcome -- re-pulling weather/sync
  // status is safe and idempotent even when the attempt failed (it just re-confirms nothing
  // changed), and avoids depending on this closure's possibly-stale `result`/`state`.
  const { trigger, state } = useSyncTrigger(() => {
    syncStatus.refresh();
    if (logOpen) syncHistory.load();
    onSyncSuccess?.();
  });

  function toggleLog() {
    const next = !logOpen;
    setLogOpen(next);
    if (next) syncHistory.load();
  }

  const ok = syncStatus.data ? !syncStatus.data.is_stale && syncStatus.data.synchronization_status !== "failed" : true;

  return (
    <div className={`glass-chip ${styles.strip}`}>
      <span className={`${styles.chip} ${ok ? styles.ok : styles.failed}`} role="status">
        <span className={styles.dot} aria-hidden="true" />
        {ok ? "Sync ok" : "Sync issue"}
      </span>

      <button type="button" className={styles.lastSyncedButton} onClick={toggleLog} aria-expanded={logOpen}>
        {syncStatus.data?.last_synchronized_at
          ? `Last synced ${relativeTimeFromNow(syncStatus.data.last_synchronized_at)}`
          : "Sync history"}
        {" ▾"}
      </button>

      <button
        type="button"
        className={styles.refreshButton}
        onClick={trigger}
        disabled={state === "loading"}
        aria-label="Refresh weather data now"
      >
        {state === "loading" && <span className={styles.spinner} aria-hidden="true" />}
        {state === "loading" ? "Refreshing…" : "Refresh now"}
      </button>

      <div className={`${styles.accordion} ${logOpen ? styles.open : ""}`}>
        <SyncLogPanel entries={syncHistory.data} status={syncHistory.status} />
      </div>
    </div>
  );
}
