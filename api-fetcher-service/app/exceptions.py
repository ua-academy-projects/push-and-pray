class ExternalServiceError(Exception):
    """Base exception for external service failures."""


class ExternalServiceTimeoutError(ExternalServiceError):
    """Raised when an HTTP request times out."""


class ExternalServiceResponseError(ExternalServiceError):
    """Raised when a service returns invalid or unsuccessful data."""


class BackendServiceError(Exception):
    """Raised when the Backend Service request fails."""