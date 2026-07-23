import styles from "./Header.module.css";

/** Branding only -- sync status, last-synced time, and the refresh control now live in
 * StatusStrip, which sits directly below the Hero. */
export function Header() {
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
    </header>
  );
}
