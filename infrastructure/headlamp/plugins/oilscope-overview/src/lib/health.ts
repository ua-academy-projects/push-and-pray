export type WorkloadKind = 'Deployment' | 'StatefulSet';

export type WorkloadState = 'ready' | 'degraded' | 'down' | 'scaledToZero' | 'missing';

export interface ExpectedWorkload {
  name: string;
  kind: WorkloadKind;
  label: string;
}

export interface WorkloadLike {
  metadata?: { name?: string };
  spec?: { replicas?: number; [key: string]: unknown };
  status?: {
    readyReplicas?: number;
    replicas?: number;
    [key: string]: unknown;
  };
}

export interface WorkloadSummary {
  label: string;
  name: string;
  kind: WorkloadKind;
  desired: number | null;
  ready: number | null;
  state: WorkloadState;
}

export interface ContainerStateLike {
  reason?: string;
  message?: string;
  exitCode?: number;
  [key: string]: unknown;
}

export interface ContainerStatusLike {
  name?: string;
  ready?: boolean;
  restartCount?: number;
  state?: Partial<Record<string, ContainerStateLike>>;
}

export interface PodLike {
  metadata?: { name?: string; deletionTimestamp?: string };
  status?: {
    phase?: string;
    containerStatuses?: ContainerStatusLike[];
    [key: string]: unknown;
  };
}

export interface PodProblem {
  name: string;
  phase: string;
  reason: string;
  restarts: number;
}

function stateFor(desired: number, ready: number): WorkloadState {
  if (desired === 0) {
    return 'scaledToZero';
  }

  if (ready >= desired) {
    return 'ready';
  }

  if (ready === 0) {
    return 'down';
  }

  return 'degraded';
}

export function summarizeWorkloads(
  expected: ExpectedWorkload[],
  deployments: WorkloadLike[] | null,
  statefulSets: WorkloadLike[] | null
): WorkloadSummary[] {
  const byKind: Record<WorkloadKind, WorkloadLike[] | null> = {
    Deployment: deployments,
    StatefulSet: statefulSets,
  };

  return expected.map(item => {
    const pool = byKind[item.kind];

    if (pool === null) {
      return {
        label: item.label,
        name: item.name,
        kind: item.kind,
        desired: null,
        ready: null,
        state: 'missing',
      };
    }

    const found = pool.find(candidate => candidate.metadata?.name === item.name);

    if (!found) {
      return {
        label: item.label,
        name: item.name,
        kind: item.kind,
        desired: null,
        ready: null,
        state: 'missing',
      };
    }

    const desired = found.spec?.replicas ?? 0;
    const ready = found.status?.readyReplicas ?? 0;

    return {
      label: item.label,
      name: item.name,
      kind: item.kind,
      desired,
      ready,
      state: stateFor(desired, ready),
    };
  });
}

const STARTING_REASONS = ['ContainerCreating', 'PodInitializing'];

function containerProblem(container: ContainerStatusLike): string | null {
  const state = container.state ?? {};

  const waiting = state.waiting;

  if (waiting) {
    if (waiting.reason && STARTING_REASONS.includes(waiting.reason)) {
      return null;
    }

    return waiting.reason ?? 'Waiting';
  }

  const terminated = state.terminated;

  if (terminated && terminated.exitCode !== 0) {
    return terminated.reason || `Exited ${terminated.exitCode}`;
  }

  if (container.ready === false && !state.running) {
    return 'NotReady';
  }

  return null;
}

export function failingPods(pods: PodLike[]): PodProblem[] {
  const problems: PodProblem[] = [];

  for (const pod of pods) {
    const name = pod.metadata?.name;

    if (!name || pod.metadata?.deletionTimestamp) {
      continue;
    }

    const phase = pod.status?.phase ?? 'Unknown';

    if (phase === 'Succeeded') {
      continue;
    }

    const containers = pod.status?.containerStatuses ?? [];
    const restarts = containers.reduce((total, item) => total + (item.restartCount ?? 0), 0);

    if (phase === 'Failed') {
      problems.push({ name, phase, reason: 'PodFailed', restarts });
      continue;
    }

    const reasons = containers
      .map(containerProblem)
      .filter((reason): reason is string => reason !== null);

    if (reasons.length > 0) {
      problems.push({ name, phase, reason: reasons.join(', '), restarts });
      continue;
    }

    if (phase === 'Pending' || phase === 'Unknown') {
      problems.push({ name, phase, reason: phase, restarts });
    }
  }

  return problems;
}

export interface NodeLike {
  metadata?: { name?: string };
  status?: {
    conditions?: Array<{ type?: string; status?: string; message?: string }>;
    nodeInfo?: { kubeletVersion?: string };
  };
}

export interface NodeSummary {
  name: string;
  ready: 'True' | 'False' | 'Unknown';
  kubeletVersion: string | null;
}

export function summarizeNodes(nodes: NodeLike[]): NodeSummary[] {
  return nodes.map(node => {
    const condition = (node.status?.conditions ?? []).find(item => item.type === 'Ready');
    const value = condition?.status;

    return {
      name: node.metadata?.name ?? 'unknown',
      ready: value === 'True' || value === 'False' ? value : 'Unknown',
      kubeletVersion: node.status?.nodeInfo?.kubeletVersion ?? null,
    };
  });
}

export interface PvcLike {
  metadata?: { name?: string };
  spec?: { storageClassName?: string };
  status?: { phase?: string; capacity?: { storage?: string } };
}

export interface PvcSummary {
  name: string;
  phase: string;
  capacity: string | null;
  storageClass: string | null;
}

export function summarizePvcs(claims: PvcLike[]): PvcSummary[] {
  return claims.map(claim => ({
    name: claim.metadata?.name ?? 'unknown',
    phase: claim.status?.phase ?? 'Unknown',
    capacity: claim.status?.capacity?.storage ?? null,
    storageClass: claim.spec?.storageClassName ?? null,
  }));
}
