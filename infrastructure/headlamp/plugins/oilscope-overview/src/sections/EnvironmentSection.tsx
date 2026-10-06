import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import { Alert, Box, Button, Chip, Stack, Typography } from '@mui/material';
import React from 'react';
import type { OverviewConfig } from '../lib/overviewConfig';

export function EnvironmentSection({ config }: { config: OverviewConfig }) {
  return (
    <SectionBox
      title="Environment"
      headerProps={{ noPadding: false, headerStyle: 'subsection' }}
      outterBoxProps={{ sx: { mb: 2 } }}
    >
      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mb: 2 }}>
        <Chip size="small" label={`Environment: ${config.environment}`} />
        <Chip size="small" label={`Cluster: ${config.clusterName}`} />
        <Chip size="small" label={`Namespace: ${config.namespace}`} />
      </Stack>

      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
        {config.applicationUrl ? (
          <Button
            size="small"
            variant="contained"
            href={config.applicationUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            Open OilScope
          </Button>
        ) : (
          <Typography variant="body2" color="text.secondary">
            No application URL is configured.
          </Typography>
        )}

        {config.links.map(link => (
          <Button
            key={link.url}
            size="small"
            variant="outlined"
            href={link.url}
            target="_blank"
            rel="noopener noreferrer"
          >
            {link.label}
          </Button>
        ))}
      </Stack>

      {config.rejected.length > 0 ? (
        <Alert severity="warning" variant="outlined" sx={{ mt: 2 }}>
          <Typography variant="body2" component="div">
            Part of the overview configuration was not used:
            <Box component="ul" sx={{ m: 0, pl: 2 }}>
              {config.rejected.map(reason => (
                <li key={reason}>{reason}</li>
              ))}
            </Box>
          </Typography>
        </Alert>
      ) : null}
    </SectionBox>
  );
}
