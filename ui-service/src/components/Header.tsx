import { relativeTimeFromNow } from "../utils/dateFormat";
import styles from "./Header.module.css";

interface HeaderProps {
  lastSynchronizedAt: string | null;
  isStale: boolean;
}

export function Header({ lastSynchronizedAt, isStale }: HeaderProps) {
  return (
    <header className={styles.header}>
      <div className={styles.brand}>
        <span className={styles.logo} aria-hidden="true">
          🌤️
        </span>
        <div>
          <p className={styles.wordmark}>SkyIvano</p>
          <p className={styles.location}>Ivano-Frankivsk, Ukraine</p>
        </div>
      </div>

      <div className={styles.status}>
        <span
          className={`${styles.badge} ${isStale ? styles.badgeStale : styles.badgeFresh}`}
          role="status"
        >
          <span className={styles.badgeDot} aria-hidden="true" />
          {isStale ? "Stale data" : "Live data"}
        </span>
        {lastSynchronizedAt && (
          <span className={styles.syncTime}>Updated {relativeTimeFromNow(lastSynchronizedAt)}</span>
        )}
        {/*
          "Reload displayed data" -- implemented in useWeather() as `reload()`, but
          intentionally not rendered here. The 60s poll interval already brings a successful
          scheduled sync to screen within about a minute, so a manual button adds little; the
          UI never triggers a sync either way. Uncoupled and unit-tested at the hook level
          (see tests/useWeather.test.ts). Uncomment below to re-enable:

          <button type="button" className={styles.reloadButton} onClick={reload}>
            Reload displayed data
          </button>
        */}
      </div>
    </header>
  );
}
