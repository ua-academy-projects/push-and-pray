export type OutboxState =
  | { kind: 'unavailable'; detail: string }
  | {
      kind: 'known';
      pendingCount: number;
      oldestPendingSeconds: number | null;
    };

export interface LastFetch {
  scheduledFor: string;
  fetchedAt: string;
  observations: number;
  published: number;
}

export interface CollectionStatus {
  status: string;
  provider: string | null;
  running: boolean | null;
  queue: string | null;
  nextRun: string | null;
  lastFetch: LastFetch | null;
  lastError: string | null;
  outbox: OutboxState;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null;
}

function asFiniteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export function parseOutbox(value: unknown): OutboxState {
  const record = asRecord(value);

  if (!record) {
    return {
      kind: 'unavailable',
      detail: 'The health payload carried no outbox object.',
    };
  }

  const reported = asString(record.error);

  if (reported) {
    return {
      kind: 'unavailable',
      detail: `The fetcher reported the outbox as "${reported}".`,
    };
  }

  const pendingCount = asFiniteNumber(record.pending_count);

  if (pendingCount === null) {
    return {
      kind: 'unavailable',
      detail: 'The outbox object carried no numeric pending_count.',
    };
  }

  return {
    kind: 'known',
    pendingCount,
    oldestPendingSeconds: asFiniteNumber(record.oldest_pending_seconds),
  };
}

function parseLastFetch(value: unknown): LastFetch | null {
  const record = asRecord(value);

  if (!record) {
    return null;
  }

  const fetchedAt = asString(record.fetched_at);
  const scheduledFor = asString(record.scheduled_for);

  if (!fetchedAt || !scheduledFor) {
    return null;
  }

  return {
    scheduledFor,
    fetchedAt,
    observations: asFiniteNumber(record.observations) ?? 0,
    published: asFiniteNumber(record.published) ?? 0,
  };
}

export function parseCollectionStatus(payload: unknown): CollectionStatus | null {
  const record = asRecord(payload);

  if (!record) {
    return null;
  }

  const status = asString(record.status);

  if (!status) {
    return null;
  }

  const schedule = asRecord(record.schedule);

  return {
    status,
    provider: asString(record.provider),
    running: typeof record.running === 'boolean' ? record.running : null,
    queue: asString(record.queue),
    nextRun: schedule ? asString(schedule.next_run) : null,
    lastFetch: parseLastFetch(record.last_result),
    lastError: asString(record.last_error),
    outbox: parseOutbox(record.outbox),
  };
}

export function fetchAgeSeconds(lastFetch: LastFetch | null, now: number): number | null {
  if (!lastFetch) {
    return null;
  }

  const parsed = Date.parse(lastFetch.fetchedAt);

  if (Number.isNaN(parsed)) {
    return null;
  }

  return Math.max(0, Math.round((now - parsed) / 1000));
}
