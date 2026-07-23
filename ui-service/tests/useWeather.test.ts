import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { POLL_INTERVAL_MS, useWeather } from "../src/hooks/useWeather";
import { buildWeatherResponse } from "./fixtures";

function mockFetchResolving(data: unknown) {
  return vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => data });
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("useWeather", () => {
  it("fetches once on mount", async () => {
    const fetchMock = mockFetchResolving(buildWeatherResponse());
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useWeather());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(result.current.status).toBe("ready");
  });

  it("polls again after POLL_INTERVAL_MS and only calls the weather endpoint", async () => {
    const fetchMock = mockFetchResolving(buildWeatherResponse());
    vi.stubGlobal("fetch", fetchMock);

    renderHook(() => useWeather());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(POLL_INTERVAL_MS);
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);

    for (const call of fetchMock.mock.calls) {
      expect(String(call[0])).toContain("/api/weather");
    }
  });

  it("does not poll before the interval elapses", async () => {
    const fetchMock = mockFetchResolving(buildWeatherResponse());
    vi.stubGlobal("fetch", fetchMock);

    renderHook(() => useWeather());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(POLL_INTERVAL_MS - 1000);
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("reload() re-fetches /api/weather on demand and never anything else", async () => {
    const fetchMock = mockFetchResolving(buildWeatherResponse());
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useWeather());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(result.current.status).toBe("ready");

    await act(async () => {
      await result.current.reload();
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    for (const call of fetchMock.mock.calls) {
      expect(String(call[0])).toContain("/api/weather");
      expect(String(call[0])).not.toContain("sync");
    }
  });

  it("sets status to error when the fetch fails, keeping any previously loaded data available", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => buildWeatherResponse() })
      .mockRejectedValueOnce(new Error("network down"));
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useWeather());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(result.current.status).toBe("ready");
    const firstData = result.current.data;

    await act(async () => {
      await result.current.reload();
    });

    expect(result.current.status).toBe("error");
    expect(result.current.data).toBe(firstData);
  });
});
