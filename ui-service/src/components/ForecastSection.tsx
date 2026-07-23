import { useForecast } from "../hooks/useForecast";
import { ForecastStrip } from "./ForecastStrip";
import styles from "./ForecastSection.module.css";

/** Always visible, no click required. Loads and fails independently of the Hero/Today data --
 * see docs/architecture.md's Averages/Forecast independence requirement. */
export function ForecastSection() {
  const forecast = useForecast(10);

  return (
    <section className={`glass-card ${styles.section}`} aria-label="10-day forecast">
      <h2 className={styles.heading}>Forecast</h2>
      {forecast.status === "loading" && !forecast.data && (
        <p className={styles.state} role="status">
          Loading forecast…
        </p>
      )}
      {forecast.status === "error" && (
        <p className={styles.state} role="alert">
          Couldn't load the forecast. Please try again shortly.
        </p>
      )}
      {forecast.status === "ready" && (forecast.data?.forecast.length ?? 0) === 0 && (
        <p className={styles.state}>No forecast data available yet.</p>
      )}
      {forecast.data && forecast.data.forecast.length > 0 && <ForecastStrip days={forecast.data.forecast} />}
    </section>
  );
}
