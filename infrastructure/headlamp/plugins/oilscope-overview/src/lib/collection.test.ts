import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fetchAgeSeconds, parseCollectionStatus, parseOutbox } from './collection.ts';

const healthy = {
  status: 'ok',
  provider: 'oilpriceapi',
  running: false,
  delivery: 'rabbitmq',
  queue: 'price_observations',
  schedule: {
    hours: [6, 18],
    timezone: 'UTC',
    next_run: '2026-10-03T18:00:00Z',
  },
  last_result: {
    scheduled_for: '2026-10-03T06:00:00Z',
    fetched_at: '2026-10-03T06:00:12Z',
    observations: 4,
    published: 4,
  },
  last_error: '',
  outbox: { pending_count: 0, oldest_pending_seconds: null },
};

test('the verified fetcher payload parses into every field the page shows', () => {
  const parsed = parseCollectionStatus(healthy);

  assert.ok(parsed);
  assert.equal(parsed.status, 'ok');
  assert.equal(parsed.provider, 'oilpriceapi');
  assert.equal(parsed.running, false);
  assert.equal(parsed.queue, 'price_observations');
  assert.equal(parsed.nextRun, '2026-10-03T18:00:00Z');
  assert.equal(parsed.lastFetch?.observations, 4);
  assert.equal(parsed.lastError, null);
  assert.deepEqual(parsed.outbox, {
    kind: 'known',
    pendingCount: 0,
    oldestPendingSeconds: null,
  });
});

test('an empty outbox is a known zero, not an unavailable reading', () => {
  assert.deepEqual(parseOutbox({ pending_count: 0, oldest_pending_seconds: null }), {
    kind: 'known',
    pendingCount: 0,
    oldestPendingSeconds: null,
  });
});

test("the fetcher's own outbox error is surfaced as unavailable", () => {
  const outbox = parseOutbox({ error: 'unavailable' });

  assert.equal(outbox.kind, 'unavailable');
  assert.match(outbox.detail, /unavailable/);
});

test('a missing or malformed outbox is unavailable, never a healthy zero', () => {
  assert.equal(parseOutbox(undefined).kind, 'unavailable');
  assert.equal(parseOutbox({}).kind, 'unavailable');
  assert.equal(parseOutbox({ pending_count: 'none' }).kind, 'unavailable');
  assert.equal(parseOutbox([]).kind, 'unavailable');
});

test('a pending backlog with no oldest age keeps the count and marks the age unknown', () => {
  const outbox = parseOutbox({
    pending_count: 12,
    oldest_pending_seconds: null,
  });

  assert.deepEqual(outbox, {
    kind: 'known',
    pendingCount: 12,
    oldestPendingSeconds: null,
  });
});

test('a payload with no status is rejected rather than assumed healthy', () => {
  assert.equal(parseCollectionStatus({ provider: 'oilpriceapi' }), null);
  assert.equal(parseCollectionStatus(null), null);
  assert.equal(parseCollectionStatus('ok'), null);
});

test('a not_ready payload keeps its status and its error', () => {
  const parsed = parseCollectionStatus({
    ...healthy,
    status: 'not_ready',
    last_error: 'dial tcp: connection refused',
  });

  assert.equal(parsed?.status, 'not_ready');
  assert.equal(parsed?.lastError, 'dial tcp: connection refused');
});

test('a run that has never completed reports no last fetch', () => {
  const parsed = parseCollectionStatus({ ...healthy, last_result: null });

  assert.equal(parsed?.lastFetch, null);
  assert.equal(fetchAgeSeconds(parsed?.lastFetch ?? null, Date.now()), null);
});

test('the last fetch age is measured from fetched_at', () => {
  const now = Date.parse('2026-10-03T06:10:12Z');
  const parsed = parseCollectionStatus(healthy);

  assert.equal(fetchAgeSeconds(parsed?.lastFetch ?? null, now), 600);
});

test('an unparseable fetched_at yields no age rather than a wrong one', () => {
  assert.equal(
    fetchAgeSeconds(
      {
        scheduledFor: 'x',
        fetchedAt: 'not-a-date',
        observations: 0,
        published: 0,
      },
      Date.now()
    ),
    null
  );
});

test('a payload captured from the running cluster parses field for field', () => {
  const live = {
    delivery: 'rabbitmq',
    last_error: '',
    last_result: {
      scheduled_for: '2026-10-04T18:00:00Z',
      fetched_at: '2026-10-04T18:44:46.193181259Z',
      observations: 3,
      published: 3,
    },
    outbox: { oldest_pending_seconds: null, pending_count: 0 },
    provider: 'oilpriceapi',
    queue: 'price_observations',
    running: false,
    schedule: { hours: [0, 6, 12, 18], next_run: '2026-10-05T00:00:00Z', timezone: 'UTC' },
    status: 'ok',
  };

  const parsed = parseCollectionStatus(live);

  assert.ok(parsed);
  assert.equal(parsed.status, 'ok');
  assert.equal(parsed.provider, 'oilpriceapi');
  assert.equal(parsed.running, false);
  assert.equal(parsed.queue, 'price_observations');
  assert.equal(parsed.nextRun, '2026-10-05T00:00:00Z');
  assert.equal(parsed.lastFetch?.observations, 3);
  assert.equal(parsed.lastError, null, 'an empty last_error must not raise an alert');
  assert.deepEqual(parsed.outbox, {
    kind: 'known',
    pendingCount: 0,
    oldestPendingSeconds: null,
  });
  assert.equal(
    fetchAgeSeconds(parsed.lastFetch, Date.parse('2026-10-04T18:54:46Z')),
    600,
    'Go writes fetched_at with nanosecond precision; the age must still resolve'
  );
});
