import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { DailyHistory } from "../src/components/DailyHistory";
import { Header } from "../src/components/Header";
import { HourlyTimeline } from "../src/components/HourlyTimeline";
import { buildWeatherResponse } from "./fixtures";

describe("Header", () => {
  it("does not render a reload/sync button -- the UI must never trigger a synchronization", () => {
    render(<Header lastSynchronizedAt={new Date().toISOString()} isStale={false} />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("shows fresh status distinctly from stale (not color-only -- text differs)", () => {
    const { rerender } = render(<Header lastSynchronizedAt={new Date().toISOString()} isStale={false} />);
    expect(screen.getByText("Live data")).toBeInTheDocument();

    rerender(<Header lastSynchronizedAt={new Date().toISOString()} isStale={true} />);
    expect(screen.getByText("Stale data")).toBeInTheDocument();
  });
});

describe("HourlyTimeline", () => {
  it("renders as a horizontally scrollable list (practical responsive-layout check)", () => {
    const hourly = buildWeatherResponse().hourly;
    render(<HourlyTimeline hourly={hourly} />);

    // role="list" on the scroll container is what makes the horizontal-scroll layout
    // (overflow-x: auto in HourlyTimeline.module.css) both stylable and screen-reader sane
    // across viewport widths -- this is the practical, jsdom-testable half of that behavior.
    expect(screen.getByRole("list")).toBeInTheDocument();
    expect(screen.getAllByRole("listitem").length).toBe(hourly.length);
  });

  it("highlights the hour closest to now", () => {
    const now = new Date();
    const hourly = [
      { ...buildWeatherResponse().hourly[0], weather_time: new Date(now.getTime() - 3_600_000).toISOString() },
      { ...buildWeatherResponse().hourly[0], weather_time: now.toISOString() },
      { ...buildWeatherResponse().hourly[0], weather_time: new Date(now.getTime() + 3_600_000).toISOString() },
    ];

    render(<HourlyTimeline hourly={hourly} />);

    expect(screen.getByText("Now")).toBeInTheDocument();
  });
});

describe("DailyHistory", () => {
  it("labels today distinctly from older days", () => {
    const today = new Date().toISOString().slice(0, 10);
    const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
    const base = buildWeatherResponse().daily[0];

    render(<DailyHistory daily={[{ ...base, weather_date: today }, { ...base, weather_date: yesterday }]} />);

    expect(screen.getByText("Today")).toBeInTheDocument();
    expect(screen.getByText("Yesterday")).toBeInTheDocument();
  });
});
