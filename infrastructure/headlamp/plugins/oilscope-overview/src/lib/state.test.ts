import assert from 'node:assert/strict';
import { test } from 'node:test';
import { classifyError, describeAge, fromQuery, isStale } from './state.ts';

test('a 403 from the Kubernetes API is forbidden, not unavailable', () => {
  const panel = classifyError({ status: 403, message: 'pods is forbidden' });

  assert.equal(panel.status, 'forbidden');
});

test('a 401 is also forbidden', () => {
  assert.equal(classifyError({ status: 401 }).status, 'forbidden');
});

test('any other failure is unavailable', () => {
  assert.equal(classifyError({ status: 500, message: 'boom' }).status, 'unavailable');
  assert.equal(classifyError({}).status, 'unavailable');
});

test('a pending query is loading, never an empty success', () => {
  assert.equal(fromQuery(null, null, Date.now()).status, 'loading');
  assert.equal(fromQuery(undefined, null, Date.now()).status, 'loading');
});

test('an empty list is a real answer, not loading', () => {
  const panel = fromQuery([], null, 1000);

  assert.equal(panel.status, 'ready');
  assert.deepEqual(panel.status === 'ready' ? panel.value : null, []);
});

test('an error wins over a stale cached value', () => {
  assert.equal(fromQuery(['pod'], { status: 403 }, 1000).status, 'forbidden');
});

test('data older than the window is stale', () => {
  const observedAt = 1_000_000;

  assert.equal(isStale(observedAt, observedAt + 119_000, 120), false);
  assert.equal(isStale(observedAt, observedAt + 121_000, 120), true);
});

test('ages are described in the largest useful unit', () => {
  const now = 10_000_000_000;

  assert.equal(describeAge(now - 5_000, now), '5s ago');
  assert.equal(describeAge(now - 120_000, now), '2m ago');
  assert.equal(describeAge(now - 7_200_000, now), '2h ago');
  assert.equal(describeAge(now - 172_800_000, now), '2d ago');
});
