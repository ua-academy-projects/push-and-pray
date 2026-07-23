import type { PeriodStatistics } from "../types/statistics";
import { conditionBucketInfo } from "../utils/conditionBucket";
import styles from "./StatCards.module.css";

interface StatCardsProps {
  stats: PeriodStatistics;
}

function round(value: number | null, digits = 1): string {
  if (value === null) return "–";
  return value.toFixed(digits);
}

/** Period-statistics summary tiles -- a quick-scan headline row above the charts. */
export function StatCards({ stats }: StatCardsProps) {
  const conditionCounts: [string, number][] = [
    ["clear", stats.clear_days],
    ["cloudy", stats.cloudy_days],
    ["rain", stats.rainy_days],
    ["snow", stats.snowy_days],
  ];

  return (
    <div className={styles.grid}>
      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>Avg temperature</div>
        <div className={styles.value}>
          {round(stats.average_temperature)}
          <span className={styles.unit}>°C</span>
        </div>
        <div className={styles.sub}>
          {round(stats.average_daily_minimum_temperature)}° – {round(stats.average_daily_maximum_temperature)}° avg range
        </div>
      </div>

      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>Extremes</div>
        <div className={styles.value}>
          {round(stats.lowest_temperature, 0)}° / {round(stats.highest_temperature, 0)}°
        </div>
        <div className={styles.sub}>
          {stats.coldest_day ?? "–"} · {stats.warmest_day ?? "–"}
        </div>
      </div>

      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>Avg humidity</div>
        <div className={styles.value}>
          {round(stats.average_humidity, 0)}
          <span className={styles.unit}>%</span>
        </div>
      </div>

      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>Precipitation</div>
        <div className={styles.value}>
          {round(stats.total_precipitation)}
          <span className={styles.unit}>mm</span>
        </div>
        <div className={styles.sub}>{round(stats.average_daily_precipitation)} mm/day avg</div>
      </div>

      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>Wind</div>
        <div className={styles.value}>
          {round(stats.average_wind_speed, 0)}
          <span className={styles.unit}>km/h</span>
        </div>
        <div className={styles.sub}>{round(stats.maximum_wind_speed, 0)} km/h max</div>
      </div>

      <div className={`glass-chip ${styles.card}`}>
        <div className={styles.label}>
          Conditions · {stats.available_days} day{stats.available_days === 1 ? "" : "s"}
        </div>
        <div className={styles.conditions}>
          {conditionCounts
            .filter(([, count]) => count > 0)
            .map(([bucket, count]) => {
              const { icon, label } = conditionBucketInfo(bucket);
              return (
                <span key={bucket} className={styles.conditionItem}>
                  <span aria-hidden="true">{icon}</span>
                  {count} {label}
                </span>
              );
            })}
        </div>
      </div>
    </div>
  );
}
