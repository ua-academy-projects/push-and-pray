import { ApiProxy } from '@kinvolk/headlamp-plugin/lib';
import { NameValueTable } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import { Alert, Box, Typography } from '@mui/material';
import React from 'react';
import { Panel, StatusChip, Unknown } from '../components/Panel';
import { type CollectionStatus, fetchAgeSeconds, parseCollectionStatus } from '../lib/collection';
import { classifyError, loading, type PanelState, ready, unavailable } from '../lib/state';

const REFRESH_MS = 30_000;

export function serviceProxyPath(namespace: string, service: string, port: string): string {
  return `/api/v1/namespaces/${namespace}/services/${service}:${port}/proxy/health`;
}

function formatSeconds(seconds: number | null): string | null {
  if (seconds === null) {
    return null;
  }

  if (seconds < 60) {
    return `${seconds}s`;
  }

  if (seconds < 3600) {
    return `${Math.floor(seconds / 60)}m`;
  }

  return `${Math.floor(seconds / 3600)}h`;
}

export function DataCollectionSection({
  namespace,
  service,
  staleAfterSeconds,
  now,
}: {
  namespace: string;
  service: { name: string; port: string } | null;
  staleAfterSeconds: number;
  now: number;
}) {
  const [state, setState] = React.useState<PanelState<CollectionStatus>>(loading());

  React.useEffect(() => {
    if (!service) {
      setState(
        unavailable('No fetcher service is configured, so the collection status cannot be read.')
      );

      return undefined;
    }

    let cancelled = false;

    async function poll() {
      try {
        const payload = await ApiProxy.request(
          serviceProxyPath(namespace, service!.name, service!.port),
          { isJSON: true },
          false
        );

        if (cancelled) {
          return;
        }

        const parsed = parseCollectionStatus(payload);

        setState(
          parsed
            ? ready(parsed, Date.now())
            : unavailable('The fetcher answered with a payload this page does not recognise.')
        );
      } catch (error) {
        if (cancelled) {
          return;
        }

        setState(classifyError(error as { status?: number; message?: string }));
      }
    }

    poll();

    const timer = setInterval(poll, REFRESH_MS);

    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [namespace, service?.name, service?.port]);

  return (
    <Panel title="Data collection" state={state} staleAfterSeconds={staleAfterSeconds} now={now}>
      {value => {
        const age = fetchAgeSeconds(value.lastFetch, now);

        const rows: Array<{ name: string; value: React.ReactNode }> = [
          {
            name: 'Fetcher status',
            value: (
              <StatusChip tone={value.status === 'ok' ? 'good' : 'bad'} label={value.status} />
            ),
          },
          { name: 'Provider', value: value.provider ?? <Unknown /> },
          {
            name: 'Collection running',
            value: value.running === null ? <Unknown /> : value.running ? 'yes' : 'no',
          },
          {
            name: 'Last successful fetch',
            value: value.lastFetch ? (
              <Typography variant="body2" component="span">
                {value.lastFetch.fetchedAt}
                {age === null ? null : ` (${formatSeconds(age)} ago)`} ·{' '}
                {value.lastFetch.observations} observations, {value.lastFetch.published} published
              </Typography>
            ) : (
              <Unknown>no completed fetch reported</Unknown>
            ),
          },
          { name: 'Next scheduled run', value: value.nextRun ?? <Unknown /> },
          { name: 'Queue', value: value.queue ?? <Unknown /> },
        ];

        if (value.outbox.kind === 'known') {
          rows.push({
            name: 'Outbox pending',
            value: (
              <Typography variant="body2" component="span">
                {value.outbox.pendingCount}
              </Typography>
            ),
          });

          rows.push({
            name: 'Oldest pending',
            value:
              value.outbox.oldestPendingSeconds === null ? (
                <Unknown>
                  {value.outbox.pendingCount === 0 ? 'nothing pending' : 'age not reported'}
                </Unknown>
              ) : (
                formatSeconds(Math.round(value.outbox.oldestPendingSeconds))
              ),
          });
        }

        return (
          <Box>
            {value.outbox.kind === 'unavailable' ? (
              <Alert severity="warning" variant="outlined" sx={{ mb: 1 }}>
                <Typography variant="body2">Outbox unavailable — {value.outbox.detail}</Typography>
              </Alert>
            ) : null}

            {value.lastError ? (
              <Alert severity="error" variant="outlined" sx={{ mb: 1 }}>
                <Typography variant="body2">Last collection error — {value.lastError}</Typography>
              </Alert>
            ) : null}

            <NameValueTable rows={rows} />
          </Box>
        );
      }}
    </Panel>
  );
}
