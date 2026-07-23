const TIME_FORMATTER = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
  timeZone: "Europe/Kyiv",
});

const WEEKDAY_FORMATTER = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: "Europe/Kyiv" });

const DATE_FORMATTER = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  timeZone: "Europe/Kyiv",
});

export function formatTime(iso: string): string {
  return TIME_FORMATTER.format(new Date(iso));
}

export function formatWeekday(dateStr: string): string {
  return WEEKDAY_FORMATTER.format(new Date(`${dateStr}T12:00:00`));
}

export function formatShortDate(dateStr: string): string {
  return DATE_FORMATTER.format(new Date(`${dateStr}T12:00:00`));
}

/** "Today" / "Yesterday" / weekday+date for anything older -- compared as Europe/Kyiv
 * calendar dates, matching how the Backend scopes "today" everywhere else. */
export function dayLabel(dateStr: string, todayStr: string): string {
  if (dateStr === todayStr) return "Today";

  const date = new Date(`${dateStr}T12:00:00`);
  const today = new Date(`${todayStr}T12:00:00`);
  const diffDays = Math.round((today.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));

  if (diffDays === 1) return "Yesterday";
  return `${formatWeekday(dateStr)}, ${formatShortDate(dateStr)}`;
}

export function kyivTodayString(): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv" }).formatToParts(new Date());
  const year = parts.find((p) => p.type === "year")?.value;
  const month = parts.find((p) => p.type === "month")?.value;
  const day = parts.find((p) => p.type === "day")?.value;
  return `${year}-${month}-${day}`;
}

/** "5 minutes ago" style label for the last-synchronized indicator. */
export function relativeTimeFromNow(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const diffMinutes = Math.round(diffMs / 60_000);

  if (diffMinutes < 1) return "just now";
  if (diffMinutes === 1) return "1 minute ago";
  if (diffMinutes < 60) return `${diffMinutes} minutes ago`;

  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours === 1) return "1 hour ago";
  if (diffHours < 24) return `${diffHours} hours ago`;

  const diffDays = Math.round(diffHours / 24);
  return diffDays === 1 ? "1 day ago" : `${diffDays} days ago`;
}
