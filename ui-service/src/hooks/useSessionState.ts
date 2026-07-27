import { useCallback, useEffect, useRef, useState } from "react";
import { getSession, putSessionState } from "../api/weatherApi";
import type { UIState, UIStatePatch } from "../types/session";

const STORAGE_KEY = "skyivano_sid";
const PATCH_DEBOUNCE_MS = 400;

export type SessionStatus = "loading" | "ready" | "error";

export interface UseSessionStateResult {
  state: UIState | null;
  status: SessionStatus;
  /** Merges a partial UI-state change locally (so callers see it applied immediately) and
   * persists it to the Backend, debounced and coalesced with any other pending change so a
   * burst of edits produces one PUT, not one per field. A no-op before the session finishes
   * loading -- there's no id yet to send it under. */
  patch: (change: UIStatePatch) => void;
}

/** One session per browser tab's storage, identified by an opaque id the Backend mints and
 * this hook keeps in localStorage -- not a cookie, so it works across the Vagrant LAN
 * deployment's separate origins without SameSite/CORS-credentials complications (see
 * docs/architecture.md). Redis, behind the Backend, holds only UI preferences here -- never
 * weather/business data. Call this once at the top of the tree (App.tsx) and pass the result
 * down; calling it more than once would race to mint two different session ids on a first
 * visit. */
export function useSessionState(): UseSessionStateResult {
  const [state, setState] = useState<UIState | null>(null);
  const [status, setStatus] = useState<SessionStatus>("loading");
  const sessionIdRef = useRef<string | null>(null);
  const pendingRef = useRef<UIStatePatch>({});
  const debounceRef = useRef<number | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    const existingId = window.localStorage.getItem(STORAGE_KEY) ?? undefined;
    getSession(existingId)
      .then((response) => {
        if (cancelled) return;
        sessionIdRef.current = response.session_id;
        window.localStorage.setItem(STORAGE_KEY, response.session_id);
        setState(response.state);
        setStatus("ready");
      })
      .catch(() => {
        // A session failure is a secondary concern -- the dashboard's actual weather data
        // doesn't depend on it, so this degrades to "no persistence this visit," not an error
        // screen. Callers just see status stay non-"ready" and skip hydration.
        if (!cancelled) setStatus("error");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const patch = useCallback((change: UIStatePatch) => {
    setState((previous) => (previous ? { ...previous, ...change } : previous));
    pendingRef.current = { ...pendingRef.current, ...change };

    window.clearTimeout(debounceRef.current);
    debounceRef.current = window.setTimeout(() => {
      const sessionId = sessionIdRef.current;
      const toSend = pendingRef.current;
      pendingRef.current = {};
      if (!sessionId) return;
      putSessionState(sessionId, toSend).catch(() => {
        // Best-effort: this change just won't survive a refresh.
      });
    }, PATCH_DEBOUNCE_MS);
  }, []);

  return { state, status, patch };
}
