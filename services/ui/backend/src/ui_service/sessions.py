from __future__ import annotations

import re
import secrets
from typing import Literal

from pydantic import BaseModel, Field

SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{32,128}$")


class SessionPreferences(BaseModel):
    selected: list[str] | None = Field(default=None, max_length=20)
    range: Literal["1", "7", "30", "90", "180", "365", "all"] = "30"
    metric: Literal["price", "change"] = "price"
    layout: Literal["separate", "compare"] = "compare"
    style: Literal["line", "area", "points"] = "line"
    table_order: Literal["asc", "desc"] = "desc"
    table_limit: Literal[25, 50, 100, 250] = 50
    scale: Literal["linear", "log"] = "linear"
    moving_average: Literal["off", "3", "7"] = "off"
    smooth: bool = True


def resolve_session_id(cookie_value: str | None) -> tuple[str, bool]:
    if cookie_value and SESSION_ID_PATTERN.fullmatch(cookie_value):
        return cookie_value, False
    return secrets.token_urlsafe(32), True
