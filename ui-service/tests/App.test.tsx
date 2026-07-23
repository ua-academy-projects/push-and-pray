import { render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "../src/App";
import { buildEmptyWeatherResponse, buildWeatherResponse } from "./fixtures";

function mockFetchOnce(data: unknown, ok = true, status = 200) {
  return vi.fn().mockResolvedValue({
    ok,
    status,
    json: async () => data,
  });
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

  it("calls GET /api/weather on mount, and it is the only network call made", async () => {
    const fetchMock = mockFetchOnce(buildWeatherResponse());
    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    await waitFor(() => expect(screen.getByText("Ivano-Frankivsk, Ukraine")).toBeInTheDocument());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain("/api/weather");
    expect(calledUrl).not.toContain("/api/weather/history");
    expect(calledUrl).not.toContain("sync");
    expect(calledUrl).not.toContain("open-meteo");
  });

  it("renders current weather, metrics, hourly, and daily sections from persisted data", async () => {
    vi.stubGlobal("fetch", mockFetchOnce(buildWeatherResponse()));

    render(<App />);

    await waitFor(() => expect(screen.getByLabelText("Current weather")).toBeInTheDocument());

    // Current weather (temperature is split across sibling text nodes: "25" and "°C")
    const currentCard = screen.getByLabelText("Current weather");
    expect(currentCard.textContent).toContain("25°C");
    expect(within(currentCard).getByText("Mainly clear")).toBeInTheDocument();

    // Metrics
    expect(screen.getByLabelText("Weather metrics")).toBeInTheDocument();
    expect(screen.getByText("61%")).toBeInTheDocument(); // humidity

    // Hourly
    expect(screen.getByLabelText("Hourly forecast for today")).toBeInTheDocument();

    // Daily
    const dailySection = screen.getByLabelText("Previous days");
    expect(dailySection).toBeInTheDocument();
    expect(within(dailySection).getByText("Today")).toBeInTheDocument();
  });

  it("shows a non-blocking, non-color-only stale warning when data is marked stale", async () => {
    vi.stubGlobal(
      "fetch",
      mockFetchOnce(
        buildWeatherResponse({ is_stale: true, stale_reason: "synchronization overdue" }),
      ),
    );

    render(<App />);

    await waitFor(() => expect(screen.getByText("Stale data")).toBeInTheDocument());

    // The warning must carry text, not just a color -- this asserts the actual wording exists.
    expect(screen.getByText(/haven't refreshed this data in a while/i)).toBeInTheDocument();
    // The rest of the dashboard must still render -- staleness is non-blocking.
    expect(screen.getByLabelText("Current weather")).toBeInTheDocument();
  });

  it("shows a friendly empty state when no data has ever been synchronized", async () => {
    vi.stubGlobal("fetch", mockFetchOnce(buildEmptyWeatherResponse()));

    render(<App />);

    await waitFor(() => expect(screen.getByText(/no weather data yet/i)).toBeInTheDocument());
    expect(screen.getByText(/hasn't been synchronized yet/i)).toBeInTheDocument();
    // Must not fabricate data
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
    vi.stubGlobal("fetch", mockFetchOnce({}, false, 500));

    render(<App />);

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
  });
});
