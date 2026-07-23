import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AveragesSection } from "../src/components/AveragesSection";
import { buildChartData, buildPeriodStatistics } from "./fixtures";

function jsonResponse(body: unknown, ok = true, status = 200) {
  return { ok, status, json: async () => body };
}

function installFetchRouter() {
  const calledUrls: string[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    calledUrls.push(url);
    if (url.includes("/api/weather/statistics")) return jsonResponse(buildPeriodStatistics());
    if (url.includes("/api/weather/charts")) return jsonResponse(buildChartData());
    throw new Error(`Unrouted fetch in test: ${url}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calledUrls };
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("AveragesSection", () => {
  it("loads period statistics and renders StatCards from real data", async () => {
    installFetchRouter();
    render(<AveragesSection />);

    await waitFor(() => expect(screen.getByText("Avg temperature")).toBeInTheDocument());
    expect(screen.getByText(/19\.4/)).toBeInTheDocument(); // average_temperature from the fixture
  });

  it("renders all five chart panels, each backed by an <svg>", async () => {
    installFetchRouter();
    render(<AveragesSection />);

    await waitFor(() => expect(screen.getByText(/Temperature \(avg/)).toBeInTheDocument());

    const titles = [
      /Temperature \(avg/,
      /Humidity \(avg\)/,
      /Precipitation \(total\)/,
      /Wind speed \(avg \/ max\)/,
      /Condition distribution/,
    ];
    for (const title of titles) {
      const heading = screen.getByText(title);
      const panel = heading.parentElement as HTMLElement;
      await waitFor(() => expect(panel.querySelector("svg")).toBeInTheDocument());
    }
  });

  it("re-fetches statistics and charts with new bounds when the date range preset changes", async () => {
    const { calledUrls } = installFetchRouter();
    render(<AveragesSection />);

    await waitFor(() => expect(screen.getByText("Avg temperature")).toBeInTheDocument());
    const callsBefore = calledUrls.length;

    screen.getByRole("button", { name: "Last 7 days" }).click();

    await waitFor(() => expect(calledUrls.length).toBeGreaterThan(callsBefore));
    const recentStatsCall = [...calledUrls].reverse().find((url) => url.includes("/api/weather/statistics"));
    expect(recentStatsCall).toBeDefined();
  });

  it("shows a friendly error, not a blank section, when statistics fail to load", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({}, false, 500)));
    render(<AveragesSection />);

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
    expect(screen.getByText(/couldn't load averages/i)).toBeInTheDocument();
  });

  it("shows an empty-state message when the range has no recorded days", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.includes("/statistics")) return jsonResponse(buildPeriodStatistics({ available_days: 0 }));
        if (url.includes("/charts")) return jsonResponse(buildChartData({ temperature: [], humidity: [], precipitation: [], wind: [] }));
        throw new Error(`Unrouted: ${url}`);
      }),
    );

    render(<AveragesSection />);

    await waitFor(() => expect(screen.getByText(/no recorded data for this range/i)).toBeInTheDocument());
  });
});
