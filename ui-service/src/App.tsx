import styles from "./App.module.css";
import { CurrentWeatherCard } from "./components/CurrentWeatherCard";
import { DailyHistory } from "./components/DailyHistory";
import { DataStatus } from "./components/DataStatus";
import { Header } from "./components/Header";
import { HourlyTimeline } from "./components/HourlyTimeline";
import { WeatherBackground } from "./components/WeatherBackground";
import { WeatherMetrics } from "./components/WeatherMetrics";
import { useWeather } from "./hooks/useWeather";
import { getWeatherInfo } from "./utils/weatherCode";

export default function App() {
  const { data, status } = useWeather();

  // Default background before any data has loaded, or while day/night is unknown.
  const theme = data?.current ? getWeatherInfo(data.current.weather_code, data.current.is_day).theme : "clear-night";
  const isDay = data?.current?.is_day ?? true;

  if (status === "loading") {
    return (
      <div className="app-shell">
        <WeatherBackground theme={theme} isDay={isDay} />
        <div className={`glass-card ${styles.stateCard}`} role="status" aria-live="polite">
          <div className={styles.spinner} aria-hidden="true" />
          <p className={styles.stateMessage}>Loading weather data…</p>
        </div>
      </div>
    );
  }

  if (status === "error") {
    return (
      <div className="app-shell">
        <WeatherBackground theme={theme} isDay={isDay} />
        <div className={`glass-card ${styles.stateCard} ${styles.errorCard}`} role="alert">
          <span className={styles.stateIcon} aria-hidden="true">
            ⚠️
          </span>
          <p className={styles.stateTitle}>We couldn't load weather data</p>
          <p className={styles.stateMessage}>
            Please check your connection and try again shortly. This page will keep checking automatically.
          </p>
        </div>
      </div>
    );
  }

  if (!data || !data.location || !data.current) {
    return (
      <div className="app-shell">
        <WeatherBackground theme={theme} isDay={isDay} />
        <Header lastSynchronizedAt={null} isStale={true} />
        <div className={`glass-card ${styles.stateCard}`} role="status">
          <span className={styles.stateIcon} aria-hidden="true">
            🌥️
          </span>
          <p className={styles.stateTitle}>No weather data yet</p>
          <p className={styles.stateMessage}>
            Ivano-Frankivsk's weather hasn't been synchronized yet. This page will update automatically once it has.
          </p>
        </div>
      </div>
    );
  }

  const activeTheme = getWeatherInfo(data.current.weather_code, data.current.is_day).theme;
  const today = data.daily[0];

  return (
    <div className="app-shell">
      <WeatherBackground theme={activeTheme} isDay={data.current.is_day} />

      <div className="app-content">
        <Header lastSynchronizedAt={data.last_synchronized_at} isStale={data.is_stale} />
        <CurrentWeatherCard current={data.current} today={today} />
        <WeatherMetrics current={data.current} />
        <HourlyTimeline hourly={data.hourly} />
        <DailyHistory daily={data.daily} />
        <DataStatus
          dataSource={data.data_source}
          lastSynchronizedAt={data.last_synchronized_at}
          isStale={data.is_stale}
          staleReason={data.stale_reason}
        />
      </div>
    </div>
  );
}
