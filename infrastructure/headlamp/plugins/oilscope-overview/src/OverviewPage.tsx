import { K8s } from '@kinvolk/headlamp-plugin/lib';
import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import { Alert, Box, CircularProgress, Typography } from '@mui/material';
import React from 'react';
import { type Bootstrap, loadBootstrap } from './lib/bootstrap';
import { type OverviewConfig, parseConfigMapData } from './lib/overviewConfig';
import { ApplicationHealthSection } from './sections/ApplicationHealthSection';
import { ClusterSection } from './sections/ClusterSection';
import { DataCollectionSection } from './sections/DataCollectionSection';
import { EnvironmentSection } from './sections/EnvironmentSection';
import { VersionsSection } from './sections/VersionsSection';

const CLOCK_MS = 15_000;

function useNow(): number {
  const [now, setNow] = React.useState(() => Date.now());

  React.useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), CLOCK_MS);

    return () => clearInterval(timer);
  }, []);

  return now;
}

type BootstrapState =
  | { status: 'loading' }
  | { status: 'missing' }
  | { status: 'ready'; value: Bootstrap };

function useBootstrap(): BootstrapState {
  const [state, setState] = React.useState<BootstrapState>({
    status: 'loading',
  });

  React.useEffect(() => {
    let cancelled = false;

    loadBootstrap()
      .then(value => {
        if (!cancelled) {
          setState(value ? { status: 'ready', value } : { status: 'missing' });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ status: 'missing' });
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}

function Configured({ bootstrap, now }: { bootstrap: Bootstrap; now: number }) {
  const [configMap, configMapError] = K8s.ResourceClasses.ConfigMap.useGet(
    bootstrap.configMapName,
    bootstrap.namespace
  );

  const config: OverviewConfig | null = React.useMemo(
    () => (configMap ? parseConfigMapData(configMap.jsonData?.data) : null),
    [configMap]
  );

  if (configMapError) {
    const forbidden = configMapError.status === 401 || configMapError.status === 403;

    return (
      <Alert severity={forbidden ? 'warning' : 'error'} variant="outlined">
        <Typography variant="body2">
          {forbidden
            ? `Forbidden — your account may not read the ConfigMap ${bootstrap.namespace}/${bootstrap.configMapName}, so this page cannot be configured.`
            : `Unavailable — the ConfigMap ${bootstrap.namespace}/${
                bootstrap.configMapName
              } could not be read: ${configMapError.message ?? 'the request failed'}.`}
        </Typography>
      </Alert>
    );
  }

  if (!configMap) {
    return (
      <Box display="flex" alignItems="center" gap={1} py={2}>
        <CircularProgress size={18} />
        <Typography variant="body2">Loading the overview configuration…</Typography>
      </Box>
    );
  }

  if (!config) {
    return (
      <Alert severity="error" variant="outlined">
        <Typography variant="body2">
          Unavailable — the ConfigMap {bootstrap.namespace}/{bootstrap.configMapName} does not carry
          a usable overview.json.
        </Typography>
      </Alert>
    );
  }

  return (
    <Box>
      <EnvironmentSection config={config} />

      <ApplicationHealthSection
        namespace={config.namespace}
        components={config.components}
        staleAfterSeconds={config.staleAfterSeconds}
        now={now}
      />

      <ClusterSection
        namespace={config.namespace}
        staleAfterSeconds={config.staleAfterSeconds}
        now={now}
      />

      <VersionsSection
        namespace={config.namespace}
        migrationJobPrefix={config.migrationJobPrefix}
        registryRefreshCronJob={config.registryRefreshCronJob}
        staleAfterSeconds={config.staleAfterSeconds}
        now={now}
      />

      <DataCollectionSection
        namespace={config.namespace}
        service={config.fetcherService}
        staleAfterSeconds={config.staleAfterSeconds}
        now={now}
      />
    </Box>
  );
}

export function OverviewPage() {
  const bootstrap = useBootstrap();
  const now = useNow();

  return (
    <SectionBox title="OilScope Overview" headerProps={{ noPadding: false, headerStyle: 'main' }}>
      {bootstrap.status === 'loading' ? (
        <Box display="flex" alignItems="center" gap={1} py={2}>
          <CircularProgress size={18} />
          <Typography variant="body2">Loading…</Typography>
        </Box>
      ) : null}

      {bootstrap.status === 'missing' ? (
        <Alert severity="error" variant="outlined">
          <Typography variant="body2">
            Unavailable — the plugin was deployed without a usable bootstrap.json, so it does not
            know which namespace and ConfigMap to read. See docs/headlamp.md.
          </Typography>
        </Alert>
      ) : null}

      {bootstrap.status === 'ready' ? <Configured bootstrap={bootstrap.value} now={now} /> : null}
    </SectionBox>
  );
}

export default OverviewPage;
