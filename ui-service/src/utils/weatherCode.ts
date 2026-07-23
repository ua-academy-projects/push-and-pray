export type WeatherTheme =
  | "clear-day"
  | "clear-night"
  | "partly-cloudy-day"
  | "partly-cloudy-night"
  | "cloudy"
  | "fog"
  | "drizzle"
  | "rain"
  | "heavy-rain"
  | "snow"
  | "thunderstorm";

export interface WeatherInfo {
  description: string;
  icon: string;
  theme: WeatherTheme;
}

interface WeatherCodeEntry {
  description: string;
  icon: { day: string; night: string };
  theme: { day: WeatherTheme; night: WeatherTheme };
}

/**
 * The single source of truth for WMO weather-code -> human meaning. Every component reads
 * weather meaning through getWeatherInfo() below -- nowhere else in the UI branches on a
 * raw numeric weather_code. See docs/architecture.md / original spec §22.
 */
const WEATHER_CODES: Record<number, WeatherCodeEntry> = {
  0: { description: "Clear sky", icon: { day: "☀️", night: "🌙" }, theme: { day: "clear-day", night: "clear-night" } },
  1: {
    description: "Mainly clear",
    icon: { day: "🌤️", night: "🌙" },
    theme: { day: "clear-day", night: "clear-night" },
  },
  2: {
    description: "Partly cloudy",
    icon: { day: "⛅", night: "☁️" },
    theme: { day: "partly-cloudy-day", night: "partly-cloudy-night" },
  },
  3: { description: "Overcast", icon: { day: "☁️", night: "☁️" }, theme: { day: "cloudy", night: "cloudy" } },
  45: { description: "Fog", icon: { day: "🌫️", night: "🌫️" }, theme: { day: "fog", night: "fog" } },
  48: { description: "Depositing rime fog", icon: { day: "🌫️", night: "🌫️" }, theme: { day: "fog", night: "fog" } },
  51: {
    description: "Light drizzle",
    icon: { day: "🌦️", night: "🌦️" },
    theme: { day: "drizzle", night: "drizzle" },
  },
  53: {
    description: "Moderate drizzle",
    icon: { day: "🌦️", night: "🌦️" },
    theme: { day: "drizzle", night: "drizzle" },
  },
  55: { description: "Dense drizzle", icon: { day: "🌧️", night: "🌧️" }, theme: { day: "rain", night: "rain" } },
  56: {
    description: "Light freezing drizzle",
    icon: { day: "🌦️", night: "🌦️" },
    theme: { day: "drizzle", night: "drizzle" },
  },
  57: {
    description: "Dense freezing drizzle",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "rain", night: "rain" },
  },
  61: { description: "Slight rain", icon: { day: "🌦️", night: "🌦️" }, theme: { day: "rain", night: "rain" } },
  63: { description: "Moderate rain", icon: { day: "🌧️", night: "🌧️" }, theme: { day: "rain", night: "rain" } },
  65: {
    description: "Heavy rain",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "heavy-rain", night: "heavy-rain" },
  },
  66: {
    description: "Light freezing rain",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "rain", night: "rain" },
  },
  67: {
    description: "Heavy freezing rain",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "heavy-rain", night: "heavy-rain" },
  },
  71: { description: "Slight snow fall", icon: { day: "🌨️", night: "🌨️" }, theme: { day: "snow", night: "snow" } },
  73: {
    description: "Moderate snow fall",
    icon: { day: "❄️", night: "❄️" },
    theme: { day: "snow", night: "snow" },
  },
  75: { description: "Heavy snow fall", icon: { day: "❄️", night: "❄️" }, theme: { day: "snow", night: "snow" } },
  77: { description: "Snow grains", icon: { day: "❄️", night: "❄️" }, theme: { day: "snow", night: "snow" } },
  80: {
    description: "Slight rain showers",
    icon: { day: "🌦️", night: "🌦️" },
    theme: { day: "rain", night: "rain" },
  },
  81: {
    description: "Moderate rain showers",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "rain", night: "rain" },
  },
  82: {
    description: "Violent rain showers",
    icon: { day: "🌧️", night: "🌧️" },
    theme: { day: "heavy-rain", night: "heavy-rain" },
  },
  85: {
    description: "Slight snow showers",
    icon: { day: "🌨️", night: "🌨️" },
    theme: { day: "snow", night: "snow" },
  },
  86: {
    description: "Heavy snow showers",
    icon: { day: "❄️", night: "❄️" },
    theme: { day: "snow", night: "snow" },
  },
  95: {
    description: "Thunderstorm",
    icon: { day: "⛈️", night: "⛈️" },
    theme: { day: "thunderstorm", night: "thunderstorm" },
  },
  96: {
    description: "Thunderstorm with slight hail",
    icon: { day: "⛈️", night: "⛈️" },
    theme: { day: "thunderstorm", night: "thunderstorm" },
  },
  99: {
    description: "Thunderstorm with heavy hail",
    icon: { day: "⛈️", night: "⛈️" },
    theme: { day: "thunderstorm", night: "thunderstorm" },
  },
};

const FALLBACK: WeatherCodeEntry = {
  description: "Unknown conditions",
  icon: { day: "🌡️", night: "🌡️" },
  theme: { day: "cloudy", night: "cloudy" },
};

export function getWeatherInfo(code: number, isDay: boolean): WeatherInfo {
  const entry = WEATHER_CODES[code] ?? FALLBACK;
  return {
    description: entry.description,
    icon: isDay ? entry.icon.day : entry.icon.night,
    theme: isDay ? entry.theme.day : entry.theme.night,
  };
}
