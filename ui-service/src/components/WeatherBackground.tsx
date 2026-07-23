import type { CSSProperties } from "react";
import type { WeatherTheme } from "../utils/weatherCode";
import styles from "./WeatherBackground.module.css";

interface WeatherBackgroundProps {
  theme: WeatherTheme;
  isDay: boolean;
}

const GRADIENTS: Record<WeatherTheme, { from: string; via: string; to: string }> = {
  "clear-day": { from: "#4facfe", via: "#63a4ff", to: "#a1c4fd" },
  "clear-night": { from: "#0f2027", via: "#203a5c", to: "#1b2a4a" },
  "partly-cloudy-day": { from: "#6a8caf", via: "#85a9c9", to: "#b8d0e6" },
  "partly-cloudy-night": { from: "#16213e", via: "#26355e", to: "#3a4a7a" },
  cloudy: { from: "#57606f", via: "#6b7688", to: "#8892a3" },
  fog: { from: "#8d99ae", via: "#a9b4c4", to: "#cdd4de" },
  drizzle: { from: "#4b6584", via: "#5f7a9c", to: "#7c93b0" },
  rain: { from: "#2c3e50", via: "#34495e", to: "#4a6178" },
  "heavy-rain": { from: "#1b2838", via: "#23334a", to: "#2f4256" },
  snow: { from: "#7f9bb3", via: "#a9c1d6", to: "#e2ecf5" },
  thunderstorm: { from: "#16161d", via: "#232336", to: "#3a3a54" },
};

/** Purely decorative, CSS-driven background. No copyrighted imagery -- gradients and
 * shapes only. Respects prefers-reduced-motion globally (see styles/global.css). */
export function WeatherBackground({ theme, isDay }: WeatherBackgroundProps) {
  const gradient = GRADIENTS[theme];
  const style = {
    "--bg-from": gradient.from,
    "--bg-via": gradient.via,
    "--bg-to": gradient.to,
  } as CSSProperties;

  const showClouds = theme === "partly-cloudy-day" || theme === "partly-cloudy-night" || theme === "cloudy";
  const showRain = theme === "drizzle" || theme === "rain";

  return (
    <div className={styles.background} style={style} aria-hidden="true">
      {isDay ? <div className={styles.sunGlow} /> : <div className={styles.moonGlow} />}
      {!isDay && <div className={styles.stars} />}

      {showClouds && (
        <>
          <div className={styles.cloudOne} />
          <div className={styles.cloudTwo} />
        </>
      )}

      {theme === "fog" && (
        <>
          <div className={styles.fogLayer} />
          <div className={styles.fogLayer} />
          <div className={styles.fogLayer} />
        </>
      )}

      {showRain && <div className={styles.rain} />}
      {theme === "heavy-rain" && <div className={styles.heavyRain} />}
      {theme === "snow" && <div className={styles.snow} />}
      {theme === "thunderstorm" && (
        <>
          <div className={styles.heavyRain} />
          <div className={styles.stormFlash} />
        </>
      )}
    </div>
  );
}
