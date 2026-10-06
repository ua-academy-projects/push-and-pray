import { K8s } from '@kinvolk/headlamp-plugin/lib';
import { Link } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import { Box, Table, TableBody, TableCell, TableHead, TableRow, Typography } from '@mui/material';
import React from 'react';
import { Panel, Scrollable, StatusChip, type StatusTone, Unknown } from '../components/Panel';
import { type NodeSummary, type PvcSummary, summarizeNodes, summarizePvcs } from '../lib/health';
import { classifyError, loading, type PanelState, ready } from '../lib/state';

const NODE_TONE: Record<NodeSummary['ready'], StatusTone> = {
  True: 'good',
  False: 'bad',
  Unknown: 'warn',
};

const CLAIM_TONE: Record<string, StatusTone> = {
  Bound: 'good',
  Pending: 'warn',
  Lost: 'bad',
};

interface NodeMetricsLike {
  metadata?: { name?: string };
  usage?: { cpu?: string; memory?: string };
}

function metricsFor(
  metrics: NodeMetricsLike[] | null,
  name: string
): { cpu: string; memory: string } | null {
  if (!metrics) {
    return null;
  }

  const found = metrics.find(item => item.metadata?.name === name);

  if (!found?.usage?.cpu || !found.usage.memory) {
    return null;
  }

  return { cpu: found.usage.cpu, memory: found.usage.memory };
}

export function ClusterSection({
  namespace,
  staleAfterSeconds,
  now,
}: {
  namespace: string;
  staleAfterSeconds: number;
  now: number;
}) {
  const [nodes, nodeError] = K8s.ResourceClasses.Node.useList();
  const [claims, claimError] = K8s.ResourceClasses.PersistentVolumeClaim.useList({ namespace });
  const [nodeMetrics, metricsError] = K8s.ResourceClasses.Node.useMetrics();

  const state: PanelState<{ nodes: NodeSummary[]; claims: PvcSummary[] }> = React.useMemo(() => {
    const error = nodeError || claimError;

    if (error) {
      return classifyError(error);
    }

    if (!nodes || !claims) {
      return loading();
    }

    return ready(
      {
        nodes: summarizeNodes(nodes.map(item => item.jsonData)),
        claims: summarizePvcs(claims.map(item => item.jsonData)),
      },
      now
    );
  }, [nodes, claims, nodeError, claimError, now]);

  const nodeByName = React.useMemo(() => {
    const index = new Map<string, (typeof nodes)[number]>();

    for (const node of nodes ?? []) {
      index.set(node.metadata.name, node);
    }

    return index;
  }, [nodes]);

  const claimByName = React.useMemo(() => {
    const index = new Map<string, (typeof claims)[number]>();

    for (const claim of claims ?? []) {
      index.set(claim.metadata.name, claim);
    }

    return index;
  }, [claims]);

  const metricsUnavailable = Boolean(metricsError) || nodeMetrics === null;

  return (
    <Panel
      title="Cluster and storage"
      state={state}
      staleAfterSeconds={staleAfterSeconds}
      now={now}
    >
      {value => (
        <Box>
          <Typography variant="subtitle2">Nodes</Typography>

          <Scrollable>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Node</TableCell>
                  <TableCell>Ready</TableCell>
                  <TableCell>kubelet</TableCell>
                  <TableCell align="right">CPU</TableCell>
                  <TableCell align="right">Memory</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {value.nodes.map(node => {
                  const object = nodeByName.get(node.name);
                  const usage = metricsFor(nodeMetrics, node.name);

                  return (
                    <TableRow key={node.name}>
                      <TableCell>
                        {object ? <Link kubeObject={object}>{node.name}</Link> : node.name}
                      </TableCell>
                      <TableCell>
                        <StatusChip tone={NODE_TONE[node.ready]} label={node.ready} />
                      </TableCell>
                      <TableCell>{node.kubeletVersion ?? <Unknown />}</TableCell>
                      <TableCell align="right">
                        {usage ? (
                          usage.cpu
                        ) : (
                          <Unknown>{metricsUnavailable ? 'unavailable' : '…'}</Unknown>
                        )}
                      </TableCell>
                      <TableCell align="right">
                        {usage ? (
                          usage.memory
                        ) : (
                          <Unknown>{metricsUnavailable ? 'unavailable' : '…'}</Unknown>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </Scrollable>

          {metricsUnavailable ? (
            <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 0.5 }}>
              Node CPU and memory are unavailable: the Metrics API did not answer, or your account
              may not read it.
            </Typography>
          ) : null}

          <Typography variant="subtitle2" sx={{ mt: 2 }}>
            Persistent volume claims in {namespace}
          </Typography>

          {value.claims.length === 0 ? (
            <Typography variant="body2" color="text.secondary">
              No persistent volume claim exists in this namespace.
            </Typography>
          ) : (
            <Scrollable>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Claim</TableCell>
                    <TableCell>Phase</TableCell>
                    <TableCell>Capacity</TableCell>
                    <TableCell>Storage class</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {value.claims.map(claim => {
                    const object = claimByName.get(claim.name);

                    return (
                      <TableRow key={claim.name}>
                        <TableCell>
                          {object ? <Link kubeObject={object}>{claim.name}</Link> : claim.name}
                        </TableCell>
                        <TableCell>
                          <StatusChip
                            tone={CLAIM_TONE[claim.phase] ?? 'warn'}
                            label={claim.phase}
                          />
                        </TableCell>
                        <TableCell>{claim.capacity ?? <Unknown />}</TableCell>
                        <TableCell>{claim.storageClass ?? <Unknown />}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </Scrollable>
          )}

          <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 1 }}>
            The managed PostgreSQL database is not a cluster node or pod. Its health is in the cloud
            monitoring console linked above.
          </Typography>
        </Box>
      )}
    </Panel>
  );
}
