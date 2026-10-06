import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import { Alert, Box, Chip, CircularProgress, Typography } from '@mui/material';
import React from 'react';
import { describeAge, isStale, type PanelState } from '../lib/state';

export type StatusTone = 'good' | 'warn' | 'bad' | 'unknown';

const TONE_COLOR: Record<StatusTone, 'success' | 'warning' | 'error' | 'default'> = {
  good: 'success',
  warn: 'warning',
  bad: 'error',
  unknown: 'default',
};

export function StatusChip({ tone, label }: { tone: StatusTone; label: string }) {
  return <Chip size="small" color={TONE_COLOR[tone]} variant="outlined" label={label} />;
}

export function Scrollable({ children }: { children: React.ReactNode }) {
  return <Box sx={{ width: '100%', overflowX: 'auto' }}>{children}</Box>;
}

export function Unknown({ children }: { children?: React.ReactNode }) {
  return (
    <Typography component="span" variant="body2" color="text.secondary">
      {children ?? 'unknown'}
    </Typography>
  );
}

export interface PanelProps<T> {
  title: string;
  state: PanelState<T>;
  staleAfterSeconds: number;
  now: number;
  emptyMessage?: string;
  isEmpty?: (value: T) => boolean;
  children: (value: T) => React.ReactNode;
}

export function Panel<T>({
  title,
  state,
  staleAfterSeconds,
  now,
  emptyMessage,
  isEmpty,
  children,
}: PanelProps<T>) {
  let body: React.ReactNode;

  if (state.status === 'loading') {
    body = (
      <Box display="flex" alignItems="center" gap={1} py={2}>
        <CircularProgress size={18} />
        <Typography variant="body2">Loading…</Typography>
      </Box>
    );
  } else if (state.status === 'forbidden') {
    body = (
      <Alert severity="warning" variant="outlined">
        <Typography variant="body2">
          Forbidden — your account may not read this. {state.detail}
        </Typography>
      </Alert>
    );
  } else if (state.status === 'unavailable') {
    body = (
      <Alert severity="error" variant="outlined">
        <Typography variant="body2">Unavailable — {state.detail}</Typography>
      </Alert>
    );
  } else if (isEmpty && isEmpty(state.value)) {
    body = (
      <Typography variant="body2" color="text.secondary" py={1}>
        {emptyMessage ?? 'Nothing to show.'}
      </Typography>
    );
  } else {
    body = children(state.value);
  }

  const stale = state.status === 'ready' && isStale(state.observedAt, now, staleAfterSeconds);

  return (
    <SectionBox
      title={title}
      headerProps={{ noPadding: false, headerStyle: 'subsection' }}
      outterBoxProps={{ sx: { mb: 2 } }}
    >
      {stale && state.status === 'ready' ? (
        <Alert severity="warning" variant="outlined" sx={{ mb: 1 }}>
          <Typography variant="body2">
            Stale — last updated {describeAge(state.observedAt, now)}.
          </Typography>
        </Alert>
      ) : null}

      {body}

      {state.status === 'ready' && !stale ? (
        <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 1 }}>
          Updated {describeAge(state.observedAt, now)}.
        </Typography>
      ) : null}
    </SectionBox>
  );
}
