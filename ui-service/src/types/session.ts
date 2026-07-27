/** Mirrors the Backend's DateRangeState -- one instance per section (Averages, History). */
export interface DateRangeState {
  preset: string;
  range_from: string | null;
  range_to: string | null;
}

/** The full set of persisted UI preferences for one browser session. */
export interface UIState {
  averages_range: DateRangeState;
  history_range: DateRangeState;
  history_open: boolean;
}

/** PUT /api/session/state body -- only send the fields that actually changed. */
export type UIStatePatch = Partial<UIState>;

export interface SessionResponse {
  session_id: string;
  state: UIState;
}
