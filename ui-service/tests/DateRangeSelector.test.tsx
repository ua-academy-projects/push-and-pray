import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { DateRangeSelector } from "../src/components/DateRangeSelector";
import type { UseDateRangeResult } from "../src/hooks/useDateRange";

function buildRange(overrides: Partial<UseDateRangeResult> = {}): UseDateRangeResult {
  return {
    preset: "30",
    from: "2026-06-01",
    to: "2026-06-30",
    setPreset: vi.fn(),
    setCustomRange: vi.fn(),
    ...overrides,
  };
}

describe("DateRangeSelector", () => {
  it("marks the active preset with aria-pressed, and no other preset", () => {
    render(<DateRangeSelector range={buildRange({ preset: "7" })} idPrefix="test" />);

    expect(screen.getByRole("button", { name: "Last 7 days" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "Last 10 days" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "Last 30 days" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "All available data" })).toHaveAttribute("aria-pressed", "false");
  });

  it("calls setPreset with the clicked preset", () => {
    const range = buildRange();
    render(<DateRangeSelector range={range} idPrefix="test" />);

    screen.getByRole("button", { name: "Last 10 days" }).click();
    expect(range.setPreset).toHaveBeenCalledWith("10");
  });

  it("no preset is marked pressed while a custom range is active", () => {
    render(<DateRangeSelector range={buildRange({ preset: "custom", from: "2026-01-01", to: "2026-01-15" })} idPrefix="test" />);

    for (const label of ["Last 7 days", "Last 10 days", "Last 30 days", "All available data"]) {
      expect(screen.getByRole("button", { name: label })).toHaveAttribute("aria-pressed", "false");
    }
  });
});
