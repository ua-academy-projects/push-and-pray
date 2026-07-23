import { relativeTimeFromNow } from "../utils/dateFormat";
import styles from "./DataStatus.module.css";

interface DataStatusProps {
  dataSource: string | null;
  lastSynchronizedAt: string | null;
  isStale: boolean;
  staleReason: string | null;
}

const FRIENDLY_STALE_REASONS: Record<string, string> = {
  "synchronization overdue": "We haven't refreshed this data in a while.",
  "latest synchronization failed": "Our last update attempt didn't go through — showing the most recent data we have.",
  "synchronization time unavailable": "We don't have a confirmed update time yet.",
};

export function DataStatus({ dataSource, lastSynchronizedAt, isStale, staleReason }: DataStatusProps) {
  const friendlyReason = staleReason ? (FRIENDLY_STALE_REASONS[staleReason] ?? "This data may be out of date.") : null;

  return (
    <footer className={`glass-card ${styles.status}`}>
      <span className={styles.source}>
        {dataSource && <span>Source: {dataSource}</span>}
        {lastSynchronizedAt && <span>· Last updated {relativeTimeFromNow(lastSynchronizedAt)}</span>}
      </span>

      {isStale && friendlyReason && (
        <span className={styles.warning} role="status">
          <span aria-hidden="true">⚠️</span> {friendlyReason}
        </span>
      )}
    </footer>
  );
}
