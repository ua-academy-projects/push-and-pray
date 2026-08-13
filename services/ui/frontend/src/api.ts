import type { Instrument, Observation, Preferences } from "./types";

async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: {
      Accept: "application/json",
      ...init?.headers,
    },
  });
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  return response.json() as Promise<T>;
}

export async function loadMarketData(): Promise<{
  latest: Observation[];
  observations: Observation[];
  instruments: Instrument[];
}> {
  const [latest, observations, instruments] = await Promise.all([
    requestJson<Observation[]>("/api/latest"),
    requestJson<Observation[]>("/api/observations?limit=5000"),
    requestJson<Instrument[]>("/api/instruments"),
  ]);
  return { latest, observations, instruments };
}

export function loadPreferences(): Promise<Preferences> {
  return requestJson<Preferences>("/api/session/preferences");
}

export function savePreferences(preferences: Preferences): Promise<Preferences> {
  return requestJson<Preferences>("/api/session/preferences", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(preferences),
  });
}
