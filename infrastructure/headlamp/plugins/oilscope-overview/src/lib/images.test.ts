import assert from 'node:assert/strict';
import { test } from 'node:test';
import { digestOf, latestJob, summarizeImages, summarizeJob } from './images.ts';

const registry = '000000000000.dkr.ecr.eu-central-1.amazonaws.com/oilscope';
const digest = 'sha256:1111111111111111111111111111111111111111111111111111111111111111';
const other = 'sha256:2222222222222222222222222222222222222222222222222222222222222222';

test('the running image ID is reported separately from the requested reference', () => {
  const [summary] = summarizeImages([
    {
      metadata: { name: 'oilscope-ui-1' },
      spec: { containers: [{ name: 'ui', image: `${registry}/ui@${digest}` }] },
      status: {
        containerStatuses: [
          {
            name: 'ui',
            image: `${registry}/ui`,
            imageID: `${registry}/ui@${digest}`,
          },
        ],
      },
    },
  ]);

  assert.equal(summary.requested, `${registry}/ui@${digest}`);
  assert.equal(summary.runningImageId, digest);
  assert.equal(summary.matchesRequest, true);
});

test('a running digest that differs from the requested one is flagged', () => {
  const [summary] = summarizeImages([
    {
      metadata: { name: 'oilscope-ui-1' },
      spec: { containers: [{ name: 'ui', image: `${registry}/ui@${digest}` }] },
      status: {
        containerStatuses: [{ name: 'ui', imageID: `${registry}/ui@${other}` }],
      },
    },
  ]);

  assert.equal(summary.matchesRequest, false);
  assert.equal(summary.runningImageId, other);
});

test('a tag-based request cannot be compared, so the match is unknown rather than true', () => {
  const [summary] = summarizeImages([
    {
      metadata: { name: 'oilscope-ui-1' },
      spec: { containers: [{ name: 'ui', image: `${registry}/ui:latest` }] },
      status: {
        containerStatuses: [{ name: 'ui', imageID: `${registry}/ui@${digest}` }],
      },
    },
  ]);

  assert.equal(summary.matchesRequest, null);
});

test('a container that has not started yet reports no running image', () => {
  const [summary] = summarizeImages([
    {
      metadata: { name: 'oilscope-ui-1' },
      spec: { containers: [{ name: 'ui', image: `${registry}/ui@${digest}` }] },
      status: {},
    },
  ]);

  assert.equal(summary.runningImageId, null);
  assert.equal(summary.matchesRequest, null);
});

test('digests are extracted from image IDs and absent ones stay null', () => {
  assert.equal(digestOf(`docker-pullable://${registry}/ui@${digest}`), digest);
  assert.equal(digestOf(`${registry}/ui:latest`), null);
  assert.equal(digestOf(null), null);
});

test('a failed job is reported failed with its message', () => {
  const summary = summarizeJob({
    metadata: { name: 'oilscope-migration-5' },
    status: {
      failed: 1,
      conditions: [{ type: 'Failed', status: 'True', message: 'BackoffLimitExceeded' }],
    },
  });

  assert.equal(summary.outcome, 'failed');
  assert.equal(summary.detail, 'BackoffLimitExceeded');
});

test('a job with no status at all is unknown, not succeeded', () => {
  assert.equal(summarizeJob({ metadata: { name: 'j' } }).outcome, 'unknown');
  assert.equal(summarizeJob({ metadata: { name: 'j' }, status: {} }).outcome, 'unknown');
});

test('succeeded and running jobs are distinguished', () => {
  assert.equal(summarizeJob({ status: { succeeded: 1 } }).outcome, 'succeeded');
  assert.equal(summarizeJob({ status: { active: 1 } }).outcome, 'running');
});

test('a job that both failed and succeeded on retry is reported failed', () => {
  assert.equal(summarizeJob({ status: { succeeded: 1, failed: 2 } }).outcome, 'failed');
});

test('the most recently started job is selected', () => {
  const chosen = latestJob([
    {
      metadata: { name: 'old' },
      status: { startTime: '2026-10-01T00:00:00Z' },
    },
    {
      metadata: { name: 'new' },
      status: { startTime: '2026-10-03T00:00:00Z' },
    },
    {
      metadata: { name: 'middle' },
      status: { startTime: '2026-10-02T00:00:00Z' },
    },
  ]);

  assert.equal(chosen?.metadata?.name, 'new');
});

test('selection falls back to creation time and an empty list yields nothing', () => {
  assert.equal(
    latestJob([
      { metadata: { name: 'a', creationTimestamp: '2026-10-01T00:00:00Z' } },
      { metadata: { name: 'b', creationTimestamp: '2026-10-02T00:00:00Z' } },
    ])?.metadata?.name,
    'b'
  );

  assert.equal(latestJob([]), null);
});
