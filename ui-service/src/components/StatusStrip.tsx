import { useState } from "react";
import { useSyncHistory } from "../hooks/useSyncHistory";
import { useSyncStatus } from "../hooks/useSyncStatus";
import { relativeTimeFromNow } from "../utils/dateFormat";
import { SyncLogPanel } from "./SyncLogPanel";
import styles from "./StatusStrip.module.css";

interface StatusStripProps {
  /** Called after a manual refresh completes successfully, so the parent can re-pull the
   * main weather data. StatusStrip owns its own sync-status/sync-history state either way. */
  onSyncSuccess?: () => void;
}

export function StatusStrip({}: StatusStripProps) {
  const [logOpen, setLogOpen] = useState(false);
  const syncStatus = useSyncStatus();
  const syncHistory = useSyncHistory();

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

      <div className={`${styles.accordion} ${logOpen ? styles.open : ""}`}>
        <SyncLogPanel entries={syncHistory.data} status={syncHistory.status} />
      </div>
    </div>
  );
}
