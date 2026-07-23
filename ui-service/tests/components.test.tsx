import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Header } from "../src/components/Header";
import { HourlyTimeline } from "../src/components/HourlyTimeline";
import { buildWeatherResponse } from "./fixtures";

describe("Header", () => {
  it("does not render a reload/sync button -- the UI must never trigger a synchronization", () => {
    render(<Header />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("renders the brand", () => {
    render(<Header />);

    expect(screen.getByText("SkyIvano")).toBeInTheDocument();
    expect(screen.getByText("Ivano-Frankivsk, Ukraine")).toBeInTheDocument();
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

  it("never renders a chart, just hours and temperatures (Today section requirement)", () => {
    const hourly = buildWeatherResponse().hourly;
    const { container } = render(<HourlyTimeline hourly={hourly} />);

    expect(container.querySelector("svg")).not.toBeInTheDocument();
  });
});
