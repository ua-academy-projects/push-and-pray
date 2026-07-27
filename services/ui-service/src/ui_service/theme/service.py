"""Application service for anonymous UI theme preferences."""

import logging

from ui_service.theme.models import Theme
from ui_service.theme.repository import ThemeRepository, ThemeRepositoryError

logger = logging.getLogger(__name__)
DEFAULT_THEME: Theme = "dark"
ALLOWED_THEMES = frozenset({"dark", "light"})


class InvalidThemeError(ValueError):
    """The requested theme is outside the supported UI preference set."""


class ThemeUnavailableError(RuntimeError):
    """Theme persistence failed its readiness check."""


class ThemeService:
    """Load and save non-business UI state through a repository boundary."""

    def __init__(self, repository: ThemeRepository) -> None:
        self._repository = repository

    @property
    def default_theme(self) -> Theme:
        return DEFAULT_THEME

    def validate_theme(self, requested_theme: str) -> Theme:
        if requested_theme == "dark":
            return "dark"
        if requested_theme == "light":
            return "light"
        raise InvalidThemeError("Theme must be 'dark' or 'light'.")

    async def load_theme(self, session_id: str) -> Theme:
        try:
            return self.validate_theme(await self._repository.get_theme(session_id))
        except ThemeRepositoryError:
            logger.warning("ui_theme_load_failed")
            return self.default_theme

    async def save_theme(self, session_id: str, requested_theme: str) -> Theme:
        theme = self.validate_theme(requested_theme)
        try:
            await self._repository.set_theme(session_id, theme)
        except ThemeRepositoryError:
            logger.warning("ui_theme_save_failed")
        return theme

    async def delete(self, session_id: str) -> None:
        try:
            await self._repository.delete_theme(session_id)
        except ThemeRepositoryError:
            logger.warning("ui_theme_delete_failed")

    async def ready(self) -> None:
        try:
            await self._repository.ping()
        except ThemeRepositoryError as error:
            raise ThemeUnavailableError("Theme storage is unavailable.") from error
