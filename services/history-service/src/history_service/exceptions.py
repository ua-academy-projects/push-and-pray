"""Safe application and Provider dependency failures."""

from datetime import datetime


class ApplicationError(Exception):
    """A failure safe to expose through the application API."""

    def __init__(self, *, status_code: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.retry_after_seconds: int | None = None
        self.reset_at: datetime | None = None


class InvalidIPAddressError(ApplicationError):
    def __init__(self) -> None:
        super().__init__(
            status_code=400,
            code="INVALID_IP_ADDRESS",
            message="The supplied value is not a valid IP address.",
        )


class NonPublicIPAddressError(ApplicationError):
    def __init__(self) -> None:
        super().__init__(
            status_code=400,
            code="NON_PUBLIC_IP_ADDRESS",
            message="The supplied IP address is not globally routable.",
        )


class ProviderServiceUnavailableError(ApplicationError):
    def __init__(self, *, code: str = "BACKEND_UNAVAILABLE") -> None:
        super().__init__(
            status_code=503,
            code=code,
            message="The reputation service is temporarily unavailable.",
        )


class ProviderServiceInvalidResponseError(ApplicationError):
    def __init__(self, *, code: str = "BACKEND_INVALID_RESPONSE") -> None:
        super().__init__(
            status_code=502,
            code=code,
            message="The reputation service returned an invalid response.",
        )


class BlacklistSnapshotConflictError(ApplicationError):
    """A provider generation was reused with a different delivery identity."""

    def __init__(self) -> None:
        super().__init__(
            status_code=409,
            code="BLACKLIST_SNAPSHOT_CONFLICT",
            message="The blacklist snapshot conflicts with an existing delivery.",
        )
