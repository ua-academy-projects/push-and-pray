import { useState } from "react";
import styles from "./App.module.css";
import { AveragesSection } from "./components/AveragesSection";
import { CurrentWeatherCard } from "./components/CurrentWeatherCard";
import { DataStatus } from "./components/DataStatus";
import { ForecastSection } from "./components/ForecastSection";
import { Header } from "./components/Header";
import { HistoryOverlay } from "./components/HistoryOverlay";
import { HourlyTimeline } from "./components/HourlyTimeline";
import { StatusStrip } from "./components/StatusStrip";
import { WeatherBackground } from "./components/WeatherBackground";
import { WeatherMetrics } from "./components/WeatherMetrics";
import { useWeather } from "./hooks/useWeather";
import { getWeatherInfo } from "./utils/weatherCode";

export default function App() {
  const { data, status, reload } = useWeather();
  const [historyOpen, setHistoryOpen] = useState(false);

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
        <Header />
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
        <Header />
        <CurrentWeatherCard current={data.current} today={today} />
        <WeatherMetrics current={data.current} />

        <StatusStrip onSyncSuccess={reload} />

        <HourlyTimeline hourly={data.hourly} />
        <ForecastSection />
        <AveragesSection />

        <button type="button" className={styles.historyTrigger} onClick={() => setHistoryOpen(true)}>
          Open history ↗
        </button>

        <DataStatus
          dataSource={data.data_source}
          lastSynchronizedAt={data.last_synchronized_at}
          isStale={data.is_stale}
          staleReason={data.stale_reason}
        />
      </div>

      <HistoryOverlay open={historyOpen} onClose={() => setHistoryOpen(false)} />
    </div>
  );
}
