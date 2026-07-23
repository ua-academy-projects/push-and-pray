import type { CurrentWeather } from "../types/weather";
import { degreesToCompass } from "../utils/windDirection";
import styles from "./WeatherMetrics.module.css";

interface WeatherMetricsProps {
  current: CurrentWeather;
}

interface MetricItem {
  label: string;
  value: string;
  icon: string;
}

export function WeatherMetrics({ current }: WeatherMetricsProps) {
  const metrics: MetricItem[] = [
    { label: "Humidity", value: `${Math.round(current.humidity)}%`, icon: "💧" },
    {
      label: "Wind",
      value: `${Math.round(current.wind_speed)} km/h ${degreesToCompass(current.wind_direction)}`,
      icon: "🌬️",
    },
    { label: "Precipitation", value: `${current.precipitation.toFixed(1)} mm`, icon: "🌧️" },
    { label: "Cloud cover", value: `${Math.round(current.cloud_cover)}%`, icon: "☁️" },
    { label: "Pressure", value: `${Math.round(current.surface_pressure)} hPa`, icon: "📊" },
  ];

  return (
    <section className={styles.grid} aria-label="Weather metrics">
      {metrics.map((metric) => (
        <div key={metric.label} className={`glass-card ${styles.metric}`}>
          <span className={styles.metricLabel}>
            <span className={styles.metricIcon} aria-hidden="true">
              {metric.icon}
            </span>{" "}
            {metric.label}
          </span>
          <span className={styles.metricValue}>{metric.value}</span>
        </div>
      ))}
    </section>
  );
}
