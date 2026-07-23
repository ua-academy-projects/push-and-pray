import type { HourlyWeather } from "../types/weather";
import { formatTime } from "../utils/dateFormat";
import { getWeatherInfo } from "../utils/weatherCode";
import styles from "./HourlyTimeline.module.css";

interface HourlyTimelineProps {
  hourly: HourlyWeather[];
}

function closestToNowIndex(hourly: HourlyWeather[]): number {
  const now = Date.now();
  let closestIndex = 0;
  let smallestDiff = Infinity;

  hourly.forEach((hour, index) => {
    const diff = Math.abs(new Date(hour.weather_time).getTime() - now);
    if (diff < smallestDiff) {
      smallestDiff = diff;
      closestIndex = index;
    }
  });

  return closestIndex;
}

export function HourlyTimeline({ hourly }: HourlyTimelineProps) {
  if (hourly.length === 0) return null;

  const currentIndex = closestToNowIndex(hourly);

  return (
    <section className={`glass-card ${styles.section}`} aria-label="Hourly forecast for today">
      <h2 className={styles.heading}>Today</h2>
      <div className={styles.scroller} role="list" tabIndex={0}>
        {hourly.map((hour, index) => {
          const { icon } = getWeatherInfo(hour.weather_code, true);
          const isNow = index === currentIndex;
          return (
            <div
              key={hour.weather_time}
              role="listitem"
              className={`${styles.hour} ${isNow ? styles.hourNow : ""}`}
              aria-current={isNow ? "time" : undefined}
            >
              <span className={styles.time}>{isNow ? "Now" : formatTime(hour.weather_time)}</span>
              <span className={styles.icon} aria-hidden="true">
                {icon}
              </span>
              <span className={styles.temp}>{Math.round(hour.temperature)}°</span>
              <span className={styles.feelsLike}>Feels {Math.round(hour.apparent_temperature)}°</span>
              {hour.precipitation_probability !== null && (
                <span className={styles.precip}>💧 {Math.round(hour.precipitation_probability)}%</span>
              )}
              <span className={styles.wind}>{Math.round(hour.wind_speed)} km/h</span>
            </div>
          );
        })}
      </div>
    </section>
  );
}
