class ExternalServiceError(Exception):
    """Base exception for external HTTP services."""


class ExternalServiceTimeoutError(ExternalServiceError):
    """Raised when an external request times out."""


class ExternalServiceResponseError(ExternalServiceError):
    """Raised when an external service returns an invalid response."""


class LocationNotFoundError(Exception):
    """Raised when a city cannot be resolved."""