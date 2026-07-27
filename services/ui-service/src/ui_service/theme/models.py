"""Validated values for the Redis theme boundary."""

from typing import Literal

from pydantic import RootModel

Theme = Literal["light", "dark"]


class RedisThemeValue(RootModel[Theme]):
    """The complete non-business value allowed in a theme Redis key."""

    root: Theme
