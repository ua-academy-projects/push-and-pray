import type { Instrument, Observation, Preferences } from "./types";

const OBSERVATION_PAGE_SIZE = 5000;

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

async function loadAllObservations(): Promise<Observation[]> {
  const observations: Observation[] = [];

  for (let offset = 0; ; offset += OBSERVATION_PAGE_SIZE) {
    const page = await requestJson<Observation[]>(
      `/api/observations?limit=${OBSERVATION_PAGE_SIZE}&offset=${offset}`,
    );
    observations.push(...page);

    if (page.length < OBSERVATION_PAGE_SIZE) return observations;
  }
}

export async function loadMarketData(): Promise<{
  latest: Observation[];
  observations: Observation[];
  instruments: Instrument[];
}> {
  const [latest, observations, instruments] = await Promise.all([
    requestJson<Observation[]>("/api/latest"),
    loadAllObservations(),
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
