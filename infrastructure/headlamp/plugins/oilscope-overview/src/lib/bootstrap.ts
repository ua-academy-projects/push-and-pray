export interface Bootstrap {
  namespace: string;
  configMapName: string;
}

export const BOOTSTRAP_URL = '/plugins/oilscope-overview/bootstrap.json';

export function parseBootstrap(raw: unknown): Bootstrap | null {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return null;
  }

  const record = raw as Record<string, unknown>;
  const namespace = record.namespace;
  const configMapName = record.configMapName;

  if (typeof namespace !== 'string' || namespace.trim() === '') {
    return null;
  }

  if (typeof configMapName !== 'string' || configMapName.trim() === '') {
    return null;
  }

  return { namespace: namespace.trim(), configMapName: configMapName.trim() };
}

export async function loadBootstrap(fetcher: typeof fetch = fetch): Promise<Bootstrap | null> {
  const response = await fetcher(BOOTSTRAP_URL, { credentials: 'same-origin' });

  if (!response.ok) {
    return null;
  }

  return parseBootstrap(await response.json());
}
