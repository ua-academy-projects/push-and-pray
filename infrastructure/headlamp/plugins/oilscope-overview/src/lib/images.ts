export interface PodSpecLike {
  metadata?: { name?: string };
  spec?: { containers?: Array<{ name?: string; image?: string }> };
  status?: {
    containerStatuses?: Array<{
      name?: string;
      image?: string;
      imageID?: string;
    }>;
  };
}

export interface ImageSummary {
  pod: string;
  container: string;
  requested: string;
  runningImageId: string | null;
  runningImage: string | null;
  matchesRequest: boolean | null;
}

export function digestOf(imageId: string | null): string | null {
  if (!imageId) {
    return null;
  }

  const marker = imageId.indexOf('sha256:');

  return marker === -1 ? null : imageId.slice(marker);
}

function requestedDigest(image: string): string | null {
  const marker = image.indexOf('@sha256:');

  return marker === -1 ? null : image.slice(marker + 1);
}

export function summarizeImages(pods: PodSpecLike[]): ImageSummary[] {
  const summaries: ImageSummary[] = [];

  for (const pod of pods) {
    const podName = pod.metadata?.name ?? 'unknown';
    const statuses = pod.status?.containerStatuses ?? [];

    for (const container of pod.spec?.containers ?? []) {
      const name = container.name ?? 'unknown';
      const requested = container.image ?? 'unknown';
      const status = statuses.find(item => item.name === name);
      const runningImageId = digestOf(status?.imageID ?? null);
      const wanted = requestedDigest(requested);

      summaries.push({
        pod: podName,
        container: name,
        requested,
        runningImageId,
        runningImage: status?.image ?? null,
        matchesRequest:
          wanted === null || runningImageId === null ? null : wanted === runningImageId,
      });
    }
  }

  return summaries;
}

export type JobOutcome = 'succeeded' | 'failed' | 'running' | 'unknown';

export interface JobLike {
  metadata?: { name?: string; creationTimestamp?: string };
  status?: {
    succeeded?: number;
    failed?: number;
    active?: number;
    startTime?: string;
    completionTime?: string;
    conditions?: Array<{
      type?: string;
      status?: string;
      message?: string;
      reason?: string;
    }>;
  };
}

export interface JobSummary {
  name: string;
  outcome: JobOutcome;
  startedAt: string | null;
  finishedAt: string | null;
  detail: string | null;
}

export function summarizeJob(job: JobLike): JobSummary {
  const status = job.status ?? {};
  const failedCondition = (status.conditions ?? []).find(
    item => item.type === 'Failed' && item.status === 'True'
  );

  let outcome: JobOutcome = 'unknown';

  if (failedCondition || (status.failed ?? 0) > 0) {
    outcome = 'failed';
  } else if ((status.succeeded ?? 0) > 0) {
    outcome = 'succeeded';
  } else if ((status.active ?? 0) > 0) {
    outcome = 'running';
  }

  return {
    name: job.metadata?.name ?? 'unknown',
    outcome,
    startedAt: status.startTime ?? null,
    finishedAt: status.completionTime ?? null,
    detail: failedCondition?.message ?? failedCondition?.reason ?? null,
  };
}

export function latestJob(jobs: JobLike[]): JobLike | null {
  if (jobs.length === 0) {
    return null;
  }

  const ordered = [...jobs].sort((left, right) => {
    const leftTime = Date.parse(left.status?.startTime ?? left.metadata?.creationTimestamp ?? '');
    const rightTime = Date.parse(
      right.status?.startTime ?? right.metadata?.creationTimestamp ?? ''
    );

    const leftValue = Number.isNaN(leftTime) ? 0 : leftTime;
    const rightValue = Number.isNaN(rightTime) ? 0 : rightTime;

    return rightValue - leftValue;
  });

  return ordered[0];
}
