import { useCharts } from "../hooks/useCharts";
import { useDateRange } from "../hooks/useDateRange";
import { useStatistics } from "../hooks/useStatistics";
import { AveragesCharts } from "./AveragesCharts";
import { DateRangeSelector } from "./DateRangeSelector";
import { StatCards } from "./StatCards";
import styles from "./AveragesSection.module.css";

/** Owns its own date-range state (independent of the History overlay's), and loads statistics
 * + chart data for that range. The only always-visible section with charts. */
export function AveragesSection() {
  const range = useDateRange("30");
  const statistics = useStatistics(range.from, range.to);
  const charts = useCharts(range.from, range.to);

  const loading = statistics.status === "loading" || charts.status === "loading";
  const error = statistics.status === "error" || charts.status === "error";
  const empty = !loading && !error && (!statistics.data || statistics.data.available_days === 0);

  return (
    <section className={`glass-card ${styles.section}`} aria-label="Averages">
      <div className={styles.header}>
        <h2 className={styles.heading}>Averages</h2>
        <DateRangeSelector range={range} idPrefix="averages" />
      </div>

      <div className={styles.body}>
        {loading && (
          <p className={styles.state} role="status">
            Loading averages…
          </p>
        )}
        {error && (
          <p className={styles.state} role="alert">
            Couldn't load averages for this range. Please try again shortly.
          </p>
        )}
        {empty && <p className={styles.state}>No recorded data for this range yet.</p>}
        {!loading && !error && !empty && statistics.data && charts.data && (
          <>
            <StatCards stats={statistics.data} />
            <AveragesCharts data={charts.data} stats={statistics.data} />
          </>
        )}
      </div>
    </section>
  );
}
