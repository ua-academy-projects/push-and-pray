"""Thin HTTP routing and public error mapping for Provider."""

import logging
from collections.abc import Awaitable, Callable
from time import monotonic
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Query, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from provider_service.exceptions import ApplicationError
from provider_service.provider import AbuseIPDBProvider, get_reputation_provider
from provider_service.schemas import (
    ErrorDetail,
    ErrorResponse,
    InternalBlacklistRequest,
    InternalBlacklistResponse,
    InternalReputationRequest,
    InternalReputationResponse,
)
from provider_service.security_logging import (
    bind_request_id,
    log_sanitized_exception,
    redact_sensitive_text,
    reset_request_id,
)
from provider_service.service import (
    ReputationProxyService,
    get_reputation_proxy_service,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def error_response(
    *,
    status_code: int,
    code: str,
    message: str,
    request_id: str,
    retry: dict[str, object] | None = None,
) -> JSONResponse:
    body = ErrorResponse(
        error=ErrorDetail(
            code=code,
            message=redact_sensitive_text(message),
            request_id=request_id,
            retry=retry,
        )
    )
    content = body.model_dump(mode="json")
    if retry is None:
        del content["error"]["retry"]
    return JSONResponse(status_code=status_code, content=content)


def current_request_id(request: Request) -> str:
    return str(getattr(request.state, "request_id", uuid4()))


async def request_id_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    supplied_request_id = request.headers.get("X-Request-ID")
    if supplied_request_id is None:
        request_id = uuid4()
    else:
        try:
            request_id = UUID(supplied_request_id)
        except ValueError:
            generated_request_id = str(uuid4())
            response: Response = error_response(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="INVALID_REQUEST_ID",
                message="X-Request-ID must be a valid UUID.",
                request_id=generated_request_id,
            )
            response.headers["X-Request-ID"] = generated_request_id
            return response

    request.state.request_id = request_id
    started = monotonic()
    token = bind_request_id(str(request_id))
    try:
        response = await call_next(request)
    finally:
        reset_request_id(token)
    response.headers["X-Request-ID"] = str(request_id)
    logger.info(
        "http_request_completed",
        extra={
            "request_id": str(request_id),
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "duration_ms": round((monotonic() - started) * 1000, 2),
        },
    )
    return response


@router.get("/health/live", tags=["health"])
async def liveness() -> dict[str, str]:
    """Confirm that the Provider process is running."""
    return {"status": "ok", "blacklist_polling_owner": "provider"}


@router.get("/health/ready", tags=["health"], response_model=None)
async def readiness(request: Request) -> dict[str, str | bool] | JSONResponse:
    """Confirm that the configured scheduler remains operational."""
    enabled = bool(getattr(request.app.state, "blacklist_scheduler_enabled", False))
    task = getattr(request.app.state, "blacklist_scheduler_task", None)
    publisher = getattr(request.app.state, "blacklist_publisher", None)
    if enabled and (
        task is None or task.done() or publisher is None or not publisher.is_connected
    ):
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "not ready",
                "blacklist_polling_owner": "provider",
                "blacklist_polling_enabled": enabled,
            },
        )
    return {
        "status": "ready",
        "blacklist_polling_owner": "provider",
        "blacklist_polling_enabled": enabled,
    }


@router.post(
    "/internal/v1/reputation-checks",
    response_model=InternalReputationResponse,
    status_code=status.HTTP_200_OK,
    responses={
        422: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
        502: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
        504: {"model": ErrorResponse},
    },
    tags=["internal-reputation"],
)
async def create_internal_reputation_check(
    payload: InternalReputationRequest,
    service: Annotated[ReputationProxyService, Depends(get_reputation_proxy_service)],
    provider: Annotated[AbuseIPDBProvider, Depends(get_reputation_provider)],
) -> InternalReputationResponse:
    """Return a validated provider result without persistence or idempotency."""
    return await service.check(payload, provider)


@router.get(
    "/internal/v1/blacklist",
    response_model=InternalBlacklistResponse,
    responses={
        422: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
        502: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
        504: {"model": ErrorResponse},
    },
    tags=["internal-blacklist"],
)
async def get_internal_blacklist(
    query: Annotated[InternalBlacklistRequest, Query()],
    service: Annotated[ReputationProxyService, Depends(get_reputation_proxy_service)],
    provider: Annotated[AbuseIPDBProvider, Depends(get_reputation_provider)],
) -> InternalBlacklistResponse:
    """Return a complete validated provider snapshot without persistence."""
    return await service.blacklist(query, provider)


async def application_exception_handler(
    request: Request, error: ApplicationError
) -> JSONResponse:
    retry = None
    retry_after_seconds = getattr(error, "retry_after_seconds", None)
    reset_at = getattr(error, "reset_at", None)
    if retry_after_seconds is not None or reset_at is not None:
        retry = {
            "retry_after_seconds": retry_after_seconds,
            "reset_at": reset_at,
        }
    logger.warning(
        "provider_request_failed",
        extra={"request_id": current_request_id(request), "error_code": error.code},
    )
    return error_response(
        status_code=error.status_code,
        code=error.code,
        message=error.message,
        request_id=current_request_id(request),
        retry=retry,
    )


async def validation_exception_handler(
    request: Request, _: RequestValidationError
) -> JSONResponse:
    return error_response(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        code="INVALID_REQUEST",
        message="The request did not satisfy the API contract.",
        request_id=current_request_id(request),
    )


async def unexpected_exception_handler(
    request: Request, error: Exception
) -> JSONResponse:
    request_id = current_request_id(request)
    log_sanitized_exception(
        logger, "unexpected_request_failure", error, request_id=request_id
    )
    return error_response(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="INTERNAL_SERVER_ERROR",
        message="An unexpected internal error occurred.",
        request_id=request_id,
    )
