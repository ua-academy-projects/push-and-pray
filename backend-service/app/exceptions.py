class OpenMeteoError(Exception):
    """Base for anything that goes wrong calling or interpreting Open-Meteo.

    request_url/status_code/duration_ms are carried on every instance (None where not
    applicable, e.g. no status_code on a timeout) so a caller can always forward whatever
    call metadata is available to the History Service's failure-recording endpoint.
    """

    def __init__(
        self,
        message: str,
        *,
        request_url: str | None = None,
        status_code: int | None = None,
        duration_ms: int | None = None,
    ):
        super().__init__(message)
        self.request_url = request_url
        self.status_code = status_code
        self.duration_ms = duration_ms


class OpenMeteoTimeoutError(OpenMeteoError):
    pass


class OpenMeteoConnectionError(OpenMeteoError):
    pass


class OpenMeteoResponseError(OpenMeteoError):
    """Non-2xx response, or a 2xx response whose body isn't valid JSON."""


class OpenMeteoDataError(OpenMeteoError):
    """2xx, valid JSON, but the payload is missing fields, has inconsistent array
    lengths, is empty, or contains an unparseable timestamp."""


class HistoryServiceError(Exception):
    def __init__(self, message: str, *, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


class HistoryServiceTimeoutError(HistoryServiceError):
    pass


class HistoryServiceUnavailableError(HistoryServiceError):
    pass


class HistoryServiceResponseError(HistoryServiceError):
    """A non-2xx response from the History Service."""


class SyncAlreadyInProgressError(Exception):
    """Raised by the internal endpoint (not the scheduler, which just skips silently)."""
