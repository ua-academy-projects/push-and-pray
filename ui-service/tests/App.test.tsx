import { render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "../src/App";
import {
  buildChartData,
  buildDailyRecordsResponse,
  buildEmptyWeatherResponse,
  buildForecastResponse,
  buildPeriodStatistics,
  buildSessionResponse,
  buildSyncLogEntries,
  buildSyncStatusResponse,
  buildSyncTriggerResult,
  buildWeatherResponse,
} from "./fixtures";

type Route = { match: (url: string) => boolean; body: unknown; ok?: boolean; status?: number };

function jsonResponse(body: unknown, ok = true, status = 200) {
  return { ok, status, json: async () => body };
}

/** Routes every fetch call by URL substring so App's many independent, parallel requests
 * (weather, sync-status, forecast, statistics, charts, and on-demand daily/sync-history) each
 * get a sensible fixture, mirroring how the real Backend answers different paths. */
function installFetchRouter(overrides: Partial<Record<string, unknown>> = {}) {
  const routes: Route[] = [
    // Checked before the generic "/api/session" route below, since that substring also
    // matches this more specific path.
    { match: (url) => url.includes("/api/session/state"), body: overrides.sessionPatch ?? buildSessionResponse() },
    { match: (url) => url.includes("/api/session"), body: overrides.session ?? buildSessionResponse() },
    { match: (url) => url.includes("/api/sync/trigger"), body: overrides.syncTrigger ?? buildSyncTriggerResult() },
    { match: (url) => url.includes("/api/weather/forecast"), body: overrides.forecast ?? buildForecastResponse() },
    { match: (url) => url.includes("/api/weather/statistics/all"), body: overrides.statisticsAll ?? buildPeriodStatistics() },
    { match: (url) => url.includes("/api/weather/statistics"), body: overrides.statistics ?? buildPeriodStatistics() },
    { match: (url) => url.includes("/api/weather/charts"), body: overrides.charts ?? buildChartData() },
    { match: (url) => url.includes("/api/weather/daily"), body: overrides.daily ?? buildDailyRecordsResponse() },
    { match: (url) => url.includes("/api/sync-status"), body: overrides.syncStatus ?? buildSyncStatusResponse() },
    { match: (url) => url.includes("/api/sync/history"), body: overrides.syncHistory ?? buildSyncLogEntries() },
    { match: (url) => url.includes("/api/weather"), body: overrides.weather ?? buildWeatherResponse() },
  ];

  const calledUrls: string[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    calledUrls.push(url);
    const route = routes.find((candidate) => candidate.match(url));
    if (!route) throw new Error(`Unrouted fetch in test: ${url}`);
    return jsonResponse(route.body);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { fetchMock, calledUrls };
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("App", () => {
  it("shows a loading state before the first response arrives", () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise(() => {})), // never resolves
    );

    render(<App />);

    expect(screen.getByText(/loading weather data/i)).toBeInTheDocument();
  });

  it("renders current weather, Today, Forecast, and Averages without any interaction", async () => {
    installFetchRouter();

    render(<App />);

    await waitFor(() => expect(screen.getByLabelText("Current weather")).toBeInTheDocument());
    const currentCard = screen.getByLabelText("Current weather");
    expect(currentCard.textContent).toContain("25°C");

    // Today -- no click required, and no chart (just an hour+temperature list)
    const todaySection = screen.getByLabelText("Hourly forecast for today");
    expect(todaySection).toBeInTheDocument();
    expect(todaySection.querySelector("svg")).not.toBeInTheDocument();

    // Forecast -- no click required, tagged "Predicted", no chart
    await waitFor(() => expect(screen.getByLabelText("10-day forecast")).toBeInTheDocument());
    const forecastSection = screen.getByLabelText("10-day forecast");
    expect(within(forecastSection).getAllByText("Predicted").length).toBeGreaterThan(0);
    expect(forecastSection.querySelector("svg")).not.toBeInTheDocument();

    // Averages -- no click required, and this is the one section with charts
    await waitFor(() => expect(screen.getByLabelText("Averages")).toBeInTheDocument());
    const averagesSection = screen.getByLabelText("Averages");
    await waitFor(() => expect(averagesSection.querySelectorAll("svg").length).toBeGreaterThan(0));
  });

  it("shows a non-blocking, non-color-only stale warning when data is marked stale", async () => {
    installFetchRouter({ weather: buildWeatherResponse({ is_stale: true, stale_reason: "synchronization overdue" }) });

    render(<App />);

    await waitFor(() => expect(screen.getByText(/haven't refreshed this data in a while/i)).toBeInTheDocument());
    // The rest of the dashboard must still render -- staleness is non-blocking.
    expect(screen.getByLabelText("Current weather")).toBeInTheDocument();
  });

  it("shows a friendly empty state when no data has ever been synchronized", async () => {
    installFetchRouter({ weather: buildEmptyWeatherResponse() });

    render(<App />);

    await waitFor(() => expect(screen.getByText(/no weather data yet/i)).toBeInTheDocument());
    expect(screen.getByText(/hasn't been synchronized yet/i)).toBeInTheDocument();
    expect(screen.queryByLabelText("Current weather")).not.toBeInTheDocument();
  });

  it("shows a friendly error state when the initial load fails, without leaking internals", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network request failed: ECONNREFUSED 127.0.0.1:8000")));

    render(<App />);

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
    expect(screen.getByText(/couldn't load weather data/i)).toBeInTheDocument();
    expect(screen.queryByText(/ECONNREFUSED/)).not.toBeInTheDocument();
  });

  it("shows a friendly error state when the backend responds with a non-2xx status", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({}, false, 500)));

    render(<App />);

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
  });

  it("keeps the History overlay closed by default and does not fetch history data until opened", async () => {
    const { calledUrls } = installFetchRouter();

    render(<App />);

    await waitFor(() => expect(screen.getByLabelText("Current weather")).toBeInTheDocument());
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(calledUrls.some((url) => url.includes("/api/weather/daily"))).toBe(false);

    screen.getByRole("button", { name: /open history/i }).click();

    await waitFor(() => expect(screen.getByRole("dialog", { name: /weather history/i })).toBeInTheDocument());
    await waitFor(() => expect(calledUrls.some((url) => url.includes("/api/weather/daily"))).toBe(true));

    screen.getByRole("button", { name: /close history/i }).click();
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  });

  it("keeps the Averages and History date ranges independent -- changing one leaves the other's preset untouched", async () => {
    installFetchRouter();

    render(<App />);
    await waitFor(() => expect(screen.getByLabelText("Averages")).toBeInTheDocument());

    const averagesSection = screen.getByLabelText("Averages");
    expect(within(averagesSection).getByRole("button", { name: "Last 30 days" })).toHaveAttribute("aria-pressed", "true");

    within(averagesSection).getByRole("button", { name: "Last 7 days" }).click();
    await waitFor(() =>
      expect(within(averagesSection).getByRole("button", { name: "Last 7 days" })).toHaveAttribute("aria-pressed", "true"),
    );

    screen.getByRole("button", { name: /open history/i }).click();
    const dialog = await screen.findByRole("dialog");
    // History defaults to its own "Last 30 days" preset, unaffected by Averages' change above.
    expect(within(dialog).getByRole("button", { name: "Last 30 days" })).toHaveAttribute("aria-pressed", "true");
  });

  it("never calls the Fetcher, Open-Meteo, or any internal endpoint directly -- only the Backend's public /api/* paths", async () => {
    const { calledUrls } = installFetchRouter();

    render(<App />);
    await waitFor(() => expect(screen.getByLabelText("Averages")).toBeInTheDocument());
    screen.getByRole("button", { name: /open history/i }).click();
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    for (const url of calledUrls) {
      expect(url).toContain("/api/");
      expect(url).not.toContain("/internal/");
      expect(url).not.toContain("open-meteo");
      expect(url.startsWith("http://localhost:8000")).toBe(true);
    }
  });

  it("runs a manual refresh through POST /api/sync/trigger, and re-pulls weather data on success", async () => {
    const { calledUrls, fetchMock } = installFetchRouter();

    render(<App />);
    await waitFor(() => expect(screen.getByLabelText("Current weather")).toBeInTheDocument());
    const weatherCallsBefore = fetchMock.mock.calls.filter((call) => String(call[0]).endsWith("/api/weather")).length;

    const refreshButton = await screen.findByRole("button", { name: /refresh weather data now/i });
    refreshButton.click();

    await waitFor(() => expect(calledUrls.some((url) => url.includes("/api/sync/trigger"))).toBe(true));
    await waitFor(() => expect(refreshButton).not.toBeDisabled());

    const weatherCallsAfter = fetchMock.mock.calls.filter((call) => String(call[0]).endsWith("/api/weather")).length;
    expect(weatherCallsAfter).toBeGreaterThan(weatherCallsBefore);

    const triggerCalls = calledUrls.filter((url) => url.includes("/sync/trigger"));
    expect(triggerCalls).toHaveLength(1);
  });
});
