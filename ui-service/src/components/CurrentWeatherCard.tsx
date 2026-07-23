import type { CurrentWeather, DailyWeather } from "../types/weather";
import { formatTime } from "../utils/dateFormat";
import { getWeatherInfo } from "../utils/weatherCode";
import styles from "./CurrentWeatherCard.module.css";

interface CurrentWeatherCardProps {
  current: CurrentWeather;
  today: DailyWeather | undefined;
}

export function CurrentWeatherCard({ current, today }: CurrentWeatherCardProps) {
  const { description, icon } = getWeatherInfo(current.weather_code, current.is_day);

  return (
    <section className={`glass-card ${styles.card}`} aria-label="Current weather">
      <div className={styles.primary}>
        <span className={styles.icon} aria-hidden="true">
          {icon}
        </span>
        <div>
          <p className={styles.temperature}>{Math.round(current.temperature)}°C</p>
          <p className={styles.description}>{description}</p>
          <span className={styles.dayNight}>{current.is_day ? "Daytime" : "Nighttime"}</span>
        </div>
      </div>

      <div className={styles.details}>
        <p className={styles.detailRow}>
          Feels like <strong>{Math.round(current.apparent_temperature)}°C</strong>
        </p>
        {today && (
          <p className={styles.minMax}>
            <span className={styles.maxTemp}>H: {Math.round(today.temperature_max)}°</span>
            <span className={styles.minTemp}>L: {Math.round(today.temperature_min)}°</span>
          </p>
        )}
        <p className={styles.detailRow}>Observed at {formatTime(current.observed_at)}</p>
      </div>
    </section>
  );
}
