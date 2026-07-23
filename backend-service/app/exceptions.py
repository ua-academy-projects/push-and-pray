class SyncAlreadyInProgressError(Exception):
    """Raised by the internal endpoint (not the scheduler, which just skips silently)."""


class PersistenceError(Exception):
    """Raised when a weather upsert or sync record write fails and has been rolled back."""


class FetcherServiceError(Exception):
    """Base for anything that goes wrong calling the Fetcher Service. Only ever raised from
    the one code path allowed to call it -- POST /api/sync/trigger, proxying to the Fetcher's
    POST /internal/fetch on behalf of the UI's manual refresh button (see docs/architecture.md
    §4 for why this is the one deliberate exception to "Backend never calls Fetcher")."""

    def __init__(self, message: str, *, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


class FetcherServiceTimeoutError(FetcherServiceError):
    pass


class FetcherServiceUnavailableError(FetcherServiceError):
    pass


class FetcherServiceResponseError(FetcherServiceError):
    """A non-2xx response from the Fetcher Service."""
