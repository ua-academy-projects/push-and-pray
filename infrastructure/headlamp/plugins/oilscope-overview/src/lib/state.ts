export type PanelState<T> =
  | { status: 'loading' }
  | { status: 'forbidden'; detail: string }
  | { status: 'unavailable'; detail: string }
  | { status: 'ready'; value: T; observedAt: number };

export interface ApiErrorLike {
  status?: number;
  message?: string;
}

export function loading<T>(): PanelState<T> {
  return { status: 'loading' };
}

export function forbidden<T>(detail: string): PanelState<T> {
  return { status: 'forbidden', detail };
}

export function unavailable<T>(detail: string): PanelState<T> {
  return { status: 'unavailable', detail };
}

export function ready<T>(value: T, observedAt: number): PanelState<T> {
  return { status: 'ready', value, observedAt };
}

export function classifyError<T>(error: ApiErrorLike): PanelState<T> {
  const message = error.message || 'The request failed.';

  if (error.status === 401 || error.status === 403) {
    return forbidden(message);
  }

  return unavailable(message);
}

export function fromQuery<T>(
  value: T | null | undefined,
  error: ApiErrorLike | null | undefined,
  observedAt: number
): PanelState<T> {
  if (error) {
    return classifyError(error);
  }

  if (value === null || value === undefined) {
    return loading();
  }

  return ready(value, observedAt);
}

export function isStale(observedAt: number, now: number, maxAgeSeconds: number): boolean {
  return now - observedAt > maxAgeSeconds * 1000;
}

export function ageSeconds(observedAt: number, now: number): number {
  return Math.max(0, Math.round((now - observedAt) / 1000));
}

export function describeAge(observedAt: number, now: number): string {
  const seconds = ageSeconds(observedAt, now);

  if (seconds < 60) {
    return `${seconds}s ago`;
  }

  if (seconds < 3600) {
    return `${Math.floor(seconds / 60)}m ago`;
  }

  if (seconds < 86400) {
    return `${Math.floor(seconds / 3600)}h ago`;
  }

  return `${Math.floor(seconds / 86400)}d ago`;
}
