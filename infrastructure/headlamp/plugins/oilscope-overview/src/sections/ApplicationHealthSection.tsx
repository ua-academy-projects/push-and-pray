import { K8s } from '@kinvolk/headlamp-plugin/lib';
import { Link } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import {
  Box,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material';
import React from 'react';
import { Panel, Scrollable, StatusChip, type StatusTone, Unknown } from '../components/Panel';
import {
  type ExpectedWorkload,
  failingPods,
  summarizeWorkloads,
  type WorkloadState,
  type WorkloadSummary,
} from '../lib/health';
import { classifyError, loading, type PanelState, ready } from '../lib/state';

const TONE: Record<WorkloadState, StatusTone> = {
  ready: 'good',
  degraded: 'warn',
  down: 'bad',
  scaledToZero: 'warn',
  missing: 'bad',
};

const LABEL: Record<WorkloadState, string> = {
  ready: 'Ready',
  degraded: 'Degraded',
  down: 'Down',
  scaledToZero: 'Scaled to zero',
  missing: 'Not found',
};

interface HealthData {
  workloads: WorkloadSummary[];
  problems: ReturnType<typeof failingPods>;
}

export function ApplicationHealthSection({
  namespace,
  components,
  staleAfterSeconds,
  now,
}: {
  namespace: string;
  components: ExpectedWorkload[];
  staleAfterSeconds: number;
  now: number;
}) {
  const [deployments, deploymentError] = K8s.ResourceClasses.Deployment.useList({ namespace });
  const [statefulSets, statefulSetError] = K8s.ResourceClasses.StatefulSet.useList({ namespace });
  const [pods, podError] = K8s.ResourceClasses.Pod.useList({ namespace });

  const state: PanelState<HealthData> = React.useMemo(() => {
    const error = deploymentError || statefulSetError || podError;

    if (error) {
      return classifyError(error);
    }

    if (!deployments || !statefulSets || !pods) {
      return loading();
    }

    return ready(
      {
        workloads: summarizeWorkloads(
          components,
          deployments.map(item => item.jsonData),
          statefulSets.map(item => item.jsonData)
        ),
        problems: failingPods(pods.map(item => item.jsonData)),
      },
      now
    );
  }, [
    deployments,
    statefulSets,
    pods,
    deploymentError,
    statefulSetError,
    podError,
    components,
    now,
  ]);

  const podByName = React.useMemo(() => {
    const index = new Map<string, (typeof pods)[number]>();

    for (const pod of pods ?? []) {
      index.set(pod.metadata.name, pod);
    }

    return index;
  }, [pods]);

  return (
    <Panel
      title="Application health"
      state={state}
      staleAfterSeconds={staleAfterSeconds}
      now={now}
      isEmpty={value => value.workloads.length === 0}
      emptyMessage="No components are configured for this environment."
    >
      {value => (
        <Box>
          <Scrollable>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Component</TableCell>
                  <TableCell>State</TableCell>
                  <TableCell align="right">Ready / desired</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {value.workloads.map(workload => (
                  <TableRow key={`${workload.kind}/${workload.name}`}>
                    <TableCell>
                      <Stack>
                        <Typography variant="body2">{workload.label}</Typography>
                        <Typography variant="caption" color="text.secondary">
                          {workload.kind} {workload.name}
                        </Typography>
                      </Stack>
                    </TableCell>
                    <TableCell>
                      <StatusChip tone={TONE[workload.state]} label={LABEL[workload.state]} />
                    </TableCell>
                    <TableCell align="right">
                      {workload.ready === null || workload.desired === null ? (
                        <Unknown />
                      ) : (
                        `${workload.ready} / ${workload.desired}`
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Scrollable>

          <Typography variant="subtitle2" sx={{ mt: 2 }}>
            Failing pods
          </Typography>

          {value.problems.length === 0 ? (
            <Typography variant="body2" color="text.secondary">
              No pod in {namespace} is reporting a problem.
            </Typography>
          ) : (
            <Scrollable>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Pod</TableCell>
                    <TableCell>Phase</TableCell>
                    <TableCell>Reason</TableCell>
                    <TableCell align="right">Restarts</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {value.problems.map(problem => {
                    const pod = podByName.get(problem.name);

                    return (
                      <TableRow key={problem.name}>
                        <TableCell>
                          {pod ? <Link kubeObject={pod}>{problem.name}</Link> : problem.name}
                        </TableCell>
                        <TableCell>{problem.phase}</TableCell>
                        <TableCell>{problem.reason}</TableCell>
                        <TableCell align="right">{problem.restarts}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </Scrollable>
          )}
        </Box>
      )}
    </Panel>
  );
}
