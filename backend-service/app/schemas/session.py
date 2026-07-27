from pydantic import BaseModel, Field


class DateRangeState(BaseModel):
    """Mirrors the UI's useDateRange hook -- one instance per section (Averages, History)."""

    preset: str = "30"  # "7" | "10" | "30" | "all" | "custom"
    range_from: str | None = None
    range_to: str | None = None


class UIState(BaseModel):
    """The full set of persisted UI preferences for one browser session. Redis holds exactly
    this shape -- never weather/business data. New UI toggles/filters get a new field here."""

    averages_range: DateRangeState = Field(default_factory=DateRangeState)
    history_range: DateRangeState = Field(default_factory=DateRangeState)
    history_open: bool = False


class UIStatePatch(BaseModel):
    """PUT /api/session/state body -- only fields the UI actually sent get merged in
    (see session_service.patch_state's exclude_unset usage)."""

    averages_range: DateRangeState | None = None
    history_range: DateRangeState | None = None
    history_open: bool | None = None


class SessionResponse(BaseModel):
    """Returned by both session endpoints. session_id is an opaque token the UI stores in
    localStorage and echoes back as the X-Session-Id header -- not a cookie, so this works
    across the Vagrant LAN's separate origins without SameSite/HTTPS requirements."""

    session_id: str
    state: UIState
