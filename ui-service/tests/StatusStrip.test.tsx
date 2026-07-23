import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { StatusStrip } from "../src/components/StatusStrip";
import { buildSyncLogEntries, buildSyncStatusResponse, buildSyncTriggerResult } from "./fixtures";

function jsonResponse(body: unknown, ok = true, status = 200) {
  return { ok, status, json: async () => body };
}

function installFetchRouter(overrides: { syncStatus?: unknown; syncHistory?: unknown; syncTrigger?: unknown } = {}) {
  const calledUrls: string[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    calledUrls.push(url);
    if (url.includes("/api/sync/trigger")) return jsonResponse(overrides.syncTrigger ?? buildSyncTriggerResult());
    if (url.includes("/api/sync/history")) return jsonResponse(overrides.syncHistory ?? buildSyncLogEntries());
    if (url.includes("/api/sync-status")) return jsonResponse(overrides.syncStatus ?? buildSyncStatusResponse());
    throw new Error(`Unrouted fetch in test: ${url}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calledUrls, fetchMock };
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("StatusStrip", () => {
  it("shows a text-based sync chip -- ok vs. issue is never conveyed by color alone", async () => {
    installFetchRouter({ syncStatus: buildSyncStatusResponse({ is_stale: false, synchronization_status: "success" }) });
    render(<StatusStrip />);

    await waitFor(() => expect(screen.getByText("Sync ok")).toBeInTheDocument());
  });

  it("shows a distinct 'Sync issue' chip when the status is stale or failed", async () => {
    installFetchRouter({ syncStatus: buildSyncStatusResponse({ is_stale: true, stale_reason: "synchronization overdue" }) });
    render(<StatusStrip />);

    await waitFor(() => expect(screen.getByText("Sync issue")).toBeInTheDocument());
  });

  it("expands and collapses the inline sync log, showing both success and failure entries with icon+label", async () => {
    installFetchRouter({
      syncHistory: buildSyncLogEntries([{ status: "success" }, { status: "failed", error_message: "Open-Meteo timeout" }]),
    });
    render(<StatusStrip />);

    const toggle = await screen.findByRole("button", { name: /sync history|last synced/i });
    expect(screen.queryByText("Success")).not.toBeInTheDocument();

    toggle.click();

    await waitFor(() => expect(screen.getByText("Success")).toBeInTheDocument());
    expect(screen.getByText("Failed")).toBeInTheDocument();
    expect(screen.getByText("Open-Meteo timeout")).toBeInTheDocument();
    expect(toggle).toHaveAttribute("aria-expanded", "true");

    toggle.click();
    await waitFor(() => expect(toggle).toHaveAttribute("aria-expanded", "false"));
  });

  it("runs the refresh control through a loading -> done cycle via POST /api/sync/trigger", async () => {
    const { calledUrls } = installFetchRouter();
    render(<StatusStrip />);

    const refreshButton = await screen.findByRole("button", { name: /refresh weather data now/i });
    refreshButton.click();

    await waitFor(() => expect(calledUrls.filter((url) => url.includes("/sync/trigger"))).toHaveLength(1));
    await waitFor(() => expect(refreshButton).not.toBeDisabled());
    expect(screen.getByText(/refresh now/i)).toBeInTheDocument();
  });

  it("calls onSyncSuccess after a manual refresh settles", async () => {
    installFetchRouter();
    const onSyncSuccess = vi.fn();
    render(<StatusStrip onSyncSuccess={onSyncSuccess} />);

    const refreshButton = await screen.findByRole("button", { name: /refresh weather data now/i });
    refreshButton.click();

    await waitFor(() => expect(onSyncSuccess).toHaveBeenCalled());
  });
});
