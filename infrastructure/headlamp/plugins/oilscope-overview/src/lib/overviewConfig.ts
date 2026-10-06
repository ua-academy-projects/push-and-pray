import type { ExpectedWorkload, WorkloadKind } from './health';

export interface OperationalLink {
  label: string;
  url: string;
}

export interface OverviewConfig {
  environment: string;
  clusterName: string;
  namespace: string;
  applicationUrl: string | null;
  links: OperationalLink[];
  components: ExpectedWorkload[];
  migrationJobPrefix: string;
  registryRefreshCronJob: string;
  fetcherService: { name: string; port: string } | null;
  staleAfterSeconds: number;
  rejected: string[];
}

export const DEFAULT_STALE_AFTER_SECONDS = 120;

const ALLOWED_KINDS: WorkloadKind[] = ['Deployment', 'StatefulSet'];

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

export function isSafeLink(url: string): boolean {
  try {
    return new URL(url).protocol === 'https:';
  } catch {
    return false;
  }
}

function parseLinks(value: unknown, rejected: string[]): OperationalLink[] {
  if (!Array.isArray(value)) {
    if (value !== undefined) {
      rejected.push('links must be an array.');
    }

    return [];
  }

  const links: OperationalLink[] = [];

  for (const entry of value) {
    const record = asRecord(entry);
    const label = record ? asString(record.label) : null;
    const url = record ? asString(record.url) : null;

    if (!label || !url) {
      rejected.push('A link entry was dropped: it needs both a label and a url.');
      continue;
    }

    if (!isSafeLink(url)) {
      rejected.push(`The link "${label}" was dropped: only https URLs are shown.`);
      continue;
    }

    links.push({ label, url });
  }

  return links;
}

function parseComponents(value: unknown, rejected: string[]): ExpectedWorkload[] {
  if (!Array.isArray(value)) {
    if (value !== undefined) {
      rejected.push('components must be an array.');
    }

    return [];
  }

  const components: ExpectedWorkload[] = [];

  for (const entry of value) {
    const record = asRecord(entry);
    const name = record ? asString(record.name) : null;
    const kindValue = record ? asString(record.kind) : null;
    const kind = ALLOWED_KINDS.find(candidate => candidate === kindValue);

    if (!name || !kind) {
      rejected.push(
        'A component entry was dropped: it needs a name and a Deployment or StatefulSet kind.'
      );
      continue;
    }

    components.push({ name, kind, label: asString(record?.label) ?? name });
  }

  return components;
}

function parseFetcherService(
  value: unknown,
  rejected: string[]
): { name: string; port: string } | null {
  const record = asRecord(value);

  if (!record) {
    return null;
  }

  const name = asString(record.name);
  const port = asString(record.port);

  if (!name || !port) {
    rejected.push('fetcherService was dropped: it needs both a name and a port.');
    return null;
  }

  return { name, port };
}

export function parseOverviewConfig(raw: unknown): OverviewConfig | null {
  const record = asRecord(raw);

  if (!record) {
    return null;
  }

  const rejected: string[] = [];
  const namespace = asString(record.namespace);

  if (!namespace) {
    return null;
  }

  const staleAfter = record.staleAfterSeconds;
  const applicationUrl = asString(record.applicationUrl);

  if (applicationUrl && !isSafeLink(applicationUrl)) {
    rejected.push('applicationUrl was dropped: only https URLs are shown.');
  }

  return {
    environment: asString(record.environment) ?? 'unknown',
    clusterName: asString(record.clusterName) ?? 'unknown',
    namespace,
    applicationUrl: applicationUrl && isSafeLink(applicationUrl) ? applicationUrl : null,
    links: parseLinks(record.links, rejected),
    components: parseComponents(record.components, rejected),
    migrationJobPrefix: asString(record.migrationJobPrefix) ?? '',
    registryRefreshCronJob: asString(record.registryRefreshCronJob) ?? '',
    fetcherService: parseFetcherService(record.fetcherService, rejected),
    staleAfterSeconds:
      typeof staleAfter === 'number' && Number.isFinite(staleAfter) && staleAfter > 0
        ? staleAfter
        : DEFAULT_STALE_AFTER_SECONDS,
    rejected,
  };
}

export function parseConfigMapData(
  data: Record<string, string> | undefined
): OverviewConfig | null {
  const raw = data?.['overview.json'];

  if (!raw) {
    return null;
  }

  try {
    return parseOverviewConfig(JSON.parse(raw));
  } catch {
    return null;
  }
}
