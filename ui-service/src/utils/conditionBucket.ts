/** The Backend's statistics endpoints report conditions as one of these four coarse buckets
 * (see backend-service/app/services/weather_condition.py), not a raw WMO weather_code --
 * separate from getWeatherInfo(), which maps a numeric code to a specific icon/description.
 * `color` is a fixed slot from the validated categorical palette (--series-1..5 in
 * global.css) assigned in a stable order, never re-cycled per which buckets are present. */
const BUCKET_INFO: Record<string, { label: string; icon: string; color: string }> = {
  clear: { label: "Clear", icon: "☀️", color: "var(--series-3)" },
  cloudy: { label: "Cloudy", icon: "☁️", color: "var(--series-5)" },
  rain: { label: "Rain", icon: "🌧️", color: "var(--series-1)" },
  snow: { label: "Snow", icon: "❄️", color: "var(--series-2)" },
};

export function conditionBucketInfo(bucket: string): { label: string; icon: string; color: string } {
  return BUCKET_INFO[bucket] ?? { label: bucket, icon: "🌡️", color: "var(--text-muted)" };
}
