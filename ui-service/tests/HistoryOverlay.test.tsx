import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { HistoryOverlay } from "../src/components/HistoryOverlay";
import { buildDailyRecordsResponse, buildSessionStateStub } from "./fixtures";

const session = buildSessionStateStub();

function jsonResponse(body: unknown) {
  return { ok: true, status: 200, json: async () => body };
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("HistoryOverlay", () => {
  it("renders nothing, and fetches nothing, while closed", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    render(<HistoryOverlay open={false} onClose={() => {}} session={session} />);

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("fetches and renders a plain list (no chart) of recorded days when open", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(buildDailyRecordsResponse())));

    const { container } = render(<HistoryOverlay open={true} onClose={() => {}} session={session} />);

    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());
    expect(screen.getByRole("list")).toBeInTheDocument();
    expect(container.querySelector("svg")).not.toBeInTheDocument();
  });

  it("calls onClose when the close button is clicked", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(buildDailyRecordsResponse())));
    const onClose = vi.fn();

    render(<HistoryOverlay open={true} onClose={onClose} session={session} />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    screen.getByRole("button", { name: /close history/i }).click();
    expect(onClose).toHaveBeenCalled();
  });

  it("owns its own date-range preset, independent of any other section's range", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(buildDailyRecordsResponse()));
    vi.stubGlobal("fetch", fetchMock);

    render(<HistoryOverlay open={true} onClose={() => {}} session={session} />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    // Defaults to the "Last 30 days" preset per useDateRange("30"), shown as pressed.
    expect(screen.getByRole("button", { name: "Last 30 days" })).toHaveAttribute("aria-pressed", "true");

    screen.getByRole("button", { name: "Last 7 days" }).click();

    await waitFor(() => expect(screen.getByRole("button", { name: "Last 7 days" })).toHaveAttribute("aria-pressed", "true"));
    expect(screen.getByRole("button", { name: "Last 30 days" })).toHaveAttribute("aria-pressed", "false");
  });

  it("shows a friendly error state, not a raw exception, when the request fails", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("ECONNREFUSED")));

    render(<HistoryOverlay open={true} onClose={() => {}} session={session} />);

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
    expect(screen.queryByText(/ECONNREFUSED/)).not.toBeInTheDocument();
  });
});
