import { K8s } from '@kinvolk/headlamp-plugin/lib';
import { Link } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import {
  Box,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Tooltip,
  Typography,
} from '@mui/material';
import React from 'react';
import { Panel, Scrollable, StatusChip, type StatusTone, Unknown } from '../components/Panel';
import {
  type ImageSummary,
  type JobOutcome,
  type JobSummary,
  latestJob,
  summarizeImages,
  summarizeJob,
} from '../lib/images';
import { classifyError, loading, type PanelState, ready } from '../lib/state';

const JOB_TONE: Record<JobOutcome, StatusTone> = {
  succeeded: 'good',
  failed: 'bad',
  running: 'warn',
  unknown: 'unknown',
};

function shortDigest(digest: string | null): string | null {
  return digest ? `${digest.slice(0, 14)}…` : null;
}

interface VersionsData {
  images: ImageSummary[];
  migration: JobSummary | null;
  registryRefresh: JobSummary | null;
}

export function VersionsSection({
  namespace,
  migrationJobPrefix,
  registryRefreshCronJob,
  staleAfterSeconds,
  now,
}: {
  namespace: string;
  migrationJobPrefix: string;
  registryRefreshCronJob: string;
  staleAfterSeconds: number;
  now: number;
}) {
  const [pods, podError] = K8s.ResourceClasses.Pod.useList({ namespace });
  const [jobs, jobError] = K8s.ResourceClasses.Job.useList({ namespace });

  const state: PanelState<VersionsData> = React.useMemo(() => {
    const error = podError || jobError;

    if (error) {
      return classifyError(error);
    }

    if (!pods || !jobs) {
      return loading();
    }

    const raw = jobs.map(item => item.jsonData);

    const migration = migrationJobPrefix
      ? latestJob(raw.filter(job => (job.metadata?.name ?? '').startsWith(migrationJobPrefix)))
      : null;

    const refresh = registryRefreshCronJob
      ? latestJob(raw.filter(job => (job.metadata?.name ?? '').startsWith(registryRefreshCronJob)))
      : null;

    return ready(
      {
        images: summarizeImages(pods.map(item => item.jsonData)),
        migration: migration ? summarizeJob(migration) : null,
        registryRefresh: refresh ? summarizeJob(refresh) : null,
      },
      now
    );
  }, [pods, jobs, podError, jobError, migrationJobPrefix, registryRefreshCronJob, now]);

  const podByName = React.useMemo(() => {
    const index = new Map<string, (typeof pods)[number]>();

    for (const pod of pods ?? []) {
      index.set(pod.metadata.name, pod);
    }

    return index;
  }, [pods]);

  function renderJob(label: string, summary: JobSummary | null, configured: boolean) {
    if (!configured) {
      return (
        <Typography variant="body2" color="text.secondary">
          {label}: not configured for this environment.
        </Typography>
      );
    }

    if (!summary) {
      return (
        <Typography variant="body2" color="text.secondary">
          {label}: no run found in {namespace}.
        </Typography>
      );
    }

    return (
      <Box display="flex" alignItems="center" gap={1} flexWrap="wrap">
        <Typography variant="body2">{label}:</Typography>
        <StatusChip tone={JOB_TONE[summary.outcome]} label={summary.outcome} />
        <Typography variant="caption" color="text.secondary">
          {summary.name}
          {summary.finishedAt ? ` · finished ${summary.finishedAt}` : ''}
          {!summary.finishedAt && summary.startedAt ? ` · started ${summary.startedAt}` : ''}
          {summary.detail ? ` · ${summary.detail}` : ''}
        </Typography>
      </Box>
    );
  }

  return (
    <Panel
      title="Deployed versions and jobs"
      state={state}
      staleAfterSeconds={staleAfterSeconds}
      now={now}
      isEmpty={value => value.images.length === 0}
      emptyMessage="No pods are running in this namespace."
    >
      {value => (
        <Box>
          <Scrollable>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Pod / container</TableCell>
                  <TableCell>Requested image</TableCell>
                  <TableCell>Running image ID</TableCell>
                  <TableCell>Match</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {value.images.map(image => {
                  const pod = podByName.get(image.pod);

                  return (
                    <TableRow key={`${image.pod}/${image.container}`}>
                      <TableCell>
                        {pod ? <Link kubeObject={pod}>{image.pod}</Link> : image.pod}
                        <Typography variant="caption" color="text.secondary" display="block">
                          {image.container}
                        </Typography>
                      </TableCell>
                      <TableCell>
                        <Tooltip title={image.requested}>
                          <Typography variant="caption" sx={{ wordBreak: 'break-all' }}>
                            {image.requested}
                          </Typography>
                        </Tooltip>
                      </TableCell>
                      <TableCell>
                        {image.runningImageId ? (
                          <Tooltip title={image.runningImageId}>
                            <Typography variant="caption">
                              {shortDigest(image.runningImageId)}
                            </Typography>
                          </Tooltip>
                        ) : (
                          <Unknown>not started</Unknown>
                        )}
                      </TableCell>
                      <TableCell>
                        {image.matchesRequest === null ? (
                          <Unknown>n/a</Unknown>
                        ) : (
                          <StatusChip
                            tone={image.matchesRequest ? 'good' : 'bad'}
                            label={image.matchesRequest ? 'same digest' : 'differs'}
                          />
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </Scrollable>

          <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', gap: 1 }}>
            {renderJob('Latest migration', value.migration, Boolean(migrationJobPrefix))}
            {renderJob('ECR refresh', value.registryRefresh, Boolean(registryRefreshCronJob))}
          </Box>
        </Box>
      )}
    </Panel>
  );
}
