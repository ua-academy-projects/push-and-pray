import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  type ExpectedWorkload,
  failingPods,
  summarizeNodes,
  summarizePvcs,
  summarizeWorkloads,
} from './health.ts';

const expected: ExpectedWorkload[] = [
  { name: 'oilscope-ui', kind: 'Deployment', label: 'UI' },
  { name: 'oilscope-history', kind: 'Deployment', label: 'History' },
  { name: 'oilscope-rabbitmq', kind: 'StatefulSet', label: 'RabbitMQ' },
];

test('a workload with every replica ready is reported ready', () => {
  const [ui] = summarizeWorkloads(
    [expected[0]],
    [
      {
        metadata: { name: 'oilscope-ui' },
        spec: { replicas: 2 },
        status: { readyReplicas: 2 },
      },
    ],
    []
  );

  assert.equal(ui.state, 'ready');
  assert.equal(ui.desired, 2);
  assert.equal(ui.ready, 2);
});

test('a partially ready workload is degraded, not ready', () => {
  const [ui] = summarizeWorkloads(
    [expected[0]],
    [
      {
        metadata: { name: 'oilscope-ui' },
        spec: { replicas: 3 },
        status: { readyReplicas: 1 },
      },
    ],
    []
  );

  assert.equal(ui.state, 'degraded');
});

test('a workload with no ready replicas is down', () => {
  const [ui] = summarizeWorkloads(
    [expected[0]],
    [{ metadata: { name: 'oilscope-ui' }, spec: { replicas: 1 }, status: {} }],
    []
  );

  assert.equal(ui.state, 'down');
  assert.equal(ui.ready, 0);
});

test('an absent workload is missing rather than healthy', () => {
  const [history] = summarizeWorkloads([expected[1]], [], []);

  assert.equal(history.state, 'missing');
  assert.equal(history.desired, null);
  assert.equal(history.ready, null);
});

test('an unreadable workload list is missing rather than healthy', () => {
  const summaries = summarizeWorkloads(expected, null, null);

  assert.deepEqual(
    summaries.map(item => item.state),
    ['missing', 'missing', 'missing']
  );
});

test('a StatefulSet is matched from the StatefulSet pool only', () => {
  const [broker] = summarizeWorkloads(
    [expected[2]],
    [
      {
        metadata: { name: 'oilscope-rabbitmq' },
        spec: { replicas: 1 },
        status: { readyReplicas: 1 },
      },
    ],
    []
  );

  assert.equal(broker.state, 'missing');
});

test('a scaled-to-zero workload is not reported as ready', () => {
  const [ui] = summarizeWorkloads(
    [expected[0]],
    [{ metadata: { name: 'oilscope-ui' }, spec: { replicas: 0 }, status: {} }],
    []
  );

  assert.equal(ui.state, 'scaledToZero');
});

test('crash looping and failed pods are reported with their reason', () => {
  const problems = failingPods([
    {
      metadata: { name: 'oilscope-ui-1' },
      status: {
        phase: 'Running',
        containerStatuses: [
          {
            name: 'ui',
            ready: false,
            restartCount: 7,
            state: { waiting: { reason: 'CrashLoopBackOff' } },
          },
        ],
      },
    },
    {
      metadata: { name: 'oilscope-fetcher-1' },
      status: { phase: 'Failed', containerStatuses: [] },
    },
  ]);

  assert.equal(problems.length, 2);
  assert.equal(problems[0].reason, 'CrashLoopBackOff');
  assert.equal(problems[0].restarts, 7);
  assert.equal(problems[1].reason, 'PodFailed');
});

test('healthy, completed and terminating pods are not reported as problems', () => {
  const problems = failingPods([
    {
      metadata: { name: 'healthy' },
      status: {
        phase: 'Running',
        containerStatuses: [{ name: 'ui', ready: true, restartCount: 0, state: { running: {} } }],
      },
    },
    { metadata: { name: 'migration' }, status: { phase: 'Succeeded' } },
    {
      metadata: {
        name: 'terminating',
        deletionTimestamp: '2026-10-03T00:00:00Z',
      },
      status: {
        phase: 'Running',
        containerStatuses: [{ name: 'ui', ready: false }],
      },
    },
  ]);

  assert.deepEqual(problems, []);
});

test('a container still being created is not yet a problem', () => {
  const problems = failingPods([
    {
      metadata: { name: 'starting' },
      status: {
        phase: 'Running',
        containerStatuses: [
          {
            name: 'ui',
            ready: false,
            restartCount: 0,
            state: { waiting: { reason: 'ContainerCreating' } },
          },
        ],
      },
    },
  ]);

  assert.deepEqual(problems, []);
});

test('a node that stopped reporting counts as Unknown, not ready', () => {
  const summaries = summarizeNodes([
    {
      metadata: { name: 'a' },
      status: { conditions: [{ type: 'Ready', status: 'True' }] },
    },
    {
      metadata: { name: 'b' },
      status: { conditions: [{ type: 'Ready', status: 'Unknown' }] },
    },
    { metadata: { name: 'c' }, status: { conditions: [] } },
  ]);

  assert.deepEqual(
    summaries.map(item => item.ready),
    ['True', 'Unknown', 'Unknown']
  );
});

test('a claim with no phase is Unknown rather than Bound', () => {
  const [claim] = summarizePvcs([{ metadata: { name: 'data' }, status: {} }]);

  assert.equal(claim.phase, 'Unknown');
  assert.equal(claim.capacity, null);
});
