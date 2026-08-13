export const eventTime = (item: {
  source_observed_at?: string;
  scheduled_for: string;
}): string => item.source_observed_at || item.scheduled_for;

export const formatPrice = (value: number | string): string =>
  new Intl.NumberFormat("uk-UA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 3,
  }).format(Number(value));

export const formatPercent = (value: number): string =>
  `${value >= 0 ? "+" : ""}${value.toFixed(2)}%`;

export const formatDateTime = (value: string | number | Date): string =>
  new Intl.DateTimeFormat("uk-UA", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
  }).format(new Date(value));

export const formatShortDate = (value: string | number): string =>
  new Intl.DateTimeFormat("uk-UA", {
    day: "2-digit",
    month: "short",
    ...(typeof value === "number" ? { hour: "2-digit" as const } : {}),
    timeZone: "UTC",
  }).format(new Date(value));

export const unitShort = (unit: string): string =>
  unit.replace(/^USD per /i, "").replace("barrel", "bbl").replace("gallon", "gal");
