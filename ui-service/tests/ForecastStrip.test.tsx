import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ForecastStrip } from "../src/components/ForecastStrip";
import { buildForecastResponse } from "./fixtures";

describe("ForecastStrip", () => {
  it("tags every day 'Predicted' and renders no chart", () => {
    const { forecast } = buildForecastResponse();
    const { container } = render(<ForecastStrip days={forecast} />);

    expect(screen.getAllByText("Predicted")).toHaveLength(forecast.length);
    expect(container.querySelector("svg")).not.toBeInTheDocument();
  });

  it("renders high/low temperatures for each day", () => {
    const { forecast } = buildForecastResponse();
    render(<ForecastStrip days={forecast.slice(0, 1)} />);

    const day = forecast[0];
    expect(screen.getByText(`${Math.round(day.temperature_max)}°`)).toBeInTheDocument();
    expect(screen.getByText(`${Math.round(day.temperature_min)}°`)).toBeInTheDocument();
  });

  it("renders nothing when there are no forecast days", () => {
    const { container } = render(<ForecastStrip days={[]} />);
    expect(container).toBeEmptyDOMElement();
  });
});
