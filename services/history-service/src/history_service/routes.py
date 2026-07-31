"""HTTP routes and error mapping for the History service."""

import logging
from collections.abc import Awaitable, Callable
from time import monotonic
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Path, Query, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from history_service.blacklist_read import (
    BlacklistReadService,
    get_blacklist_read_service,
)
from history_service.database import get_session
from history_service.exceptions import ApplicationError
from history_service.provider_client import ProviderClient, get_provider_client
from history_service.schemas import (
    ApplicationCheckRequest,
    BlacklistAnalyticsQuery,
    BlacklistAnalyticsResponse,
    BlacklistEntryPageQuery,
    BlacklistEntryQuery,
    BlacklistPage,
    BlacklistRequestSeriesQuery,
    BlacklistRequestSeriesResponse,
    BlacklistSnapshotList,
    BlacklistSnapshotListQuery,
    BlacklistStatusResponse,
    BlacklistTurnoverQuery,
    BlacklistTurnoverResponse,
    ErrorDetail,
    ErrorResponse,
    HistoryList,
    HistoryListQuery,
    HistoryRecord,
)
from history_service.security_logging import (
    log_sanitized_exception,
    redact_sensitive_text,
)
from history_service.service import (
    ApplicationService,
    HistoryService,
    HistoryUnavailableError,
    IdempotencyConflictError,
    get_application_service,
    get_history_service,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def request_id_from(request: Request) -> str:
    """Return the request ID established by middleware."""
    return str(getattr(request.state, "request_id", uuid4()))


def error_response(
    *, status_code: int, code: str, message: str, request_id: str
) -> JSONResponse:
    body = ErrorResponse(
        error=ErrorDetail(
            code=code,
            message=redact_sensitive_text(message),
            request_id=request_id,
        )
    )
    return JSONResponse(status_code=status_code, content=body.model_dump())


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
    response = await call_next(request)
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
    """Confirm that the History service process is running."""
    return {"status": "ok"}


@router.get("/health/ready", tags=["health"], response_model=None)
def readiness(
    request: Request,
    session: Annotated[Session, Depends(get_session)],
) -> dict[str, str] | JSONResponse:
    """Confirm database access and the configured RabbitMQ consumer."""
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as error:
        log_sanitized_exception(
            logger,
            "database_readiness_failed",
            error,
            request_id=request_id_from(request),
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "not ready"},
        )
    consumer_enabled = bool(
        getattr(request.app.state, "blacklist_consumer_enabled", False)
    )
    consumer = getattr(request.app.state, "blacklist_consumer", None)
    consumer_task = getattr(request.app.state, "blacklist_consumer_task", None)
    if consumer_enabled and (
        consumer is None
        or consumer_task is None
        or consumer_task.done()
        or not consumer.is_ready
    ):
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "not ready"},
        )
    return {"status": "ready"}


@router.post(
    "/api/v1/checks",
    response_model=HistoryRecord,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
        502: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
        504: {"model": ErrorResponse},
    },
    tags=["checks"],
)
def create_application_check(
    payload: ApplicationCheckRequest,
    request: Request,
    response: Response,
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[ApplicationService, Depends(get_application_service)],
    provider: Annotated[ProviderClient, Depends(get_provider_client)],
) -> HistoryRecord:
    """Validate, resolve idempotency, call Provider, and persist one result."""
    result = service.check(session, payload, request.state.request_id, provider)
    if not result.created:
        response.status_code = status.HTTP_200_OK
    return HistoryRecord.from_record(result.record)


@router.get(
    "/api/v1/checks",
    response_model=HistoryList,
    responses={400: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
    tags=["checks"],
)
def list_application_checks(
    query: Annotated[HistoryListQuery, Query()],
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[ApplicationService, Depends(get_application_service)],
) -> HistoryList:
    result, normalized_query = service.list(session, query)
    return HistoryList(
        items=[HistoryRecord.from_record(record) for record in result.records],
        limit=normalized_query.limit,
        offset=normalized_query.offset,
        total=result.total,
    )


@router.get(
    "/api/v1/checks/{history_id}",
    response_model=HistoryRecord,
    responses={404: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
    tags=["checks"],
)
def get_application_check(
    history_id: Annotated[int, Path(gt=0)],
    request: Request,
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[HistoryService, Depends(get_history_service)],
) -> HistoryRecord | JSONResponse:
    record = service.get(session, history_id)
    if record is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="HISTORY_RECORD_NOT_FOUND",
            message="The requested history record does not exist.",
            request_id=request_id_from(request),
        )
    return HistoryRecord.from_record(record)


@router.get(
    "/api/v1/blacklist/status",
    response_model=BlacklistStatusResponse,
    responses={503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_blacklist_status(
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistStatusResponse:
    return service.status(session)


@router.get(
    "/api/v1/blacklist/analytics",
    response_model=BlacklistAnalyticsResponse,
    responses={503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_blacklist_analytics(
    query: Annotated[BlacklistAnalyticsQuery, Query()],
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistAnalyticsResponse:
    """Return bounded MariaDB-derived analytics without provider activity."""
    return service.analytics(session, query)


@router.get(
    "/api/v1/blacklist/analytics/turnover",
    response_model=BlacklistTurnoverResponse,
    responses={503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_blacklist_turnover(
    query: Annotated[BlacklistTurnoverQuery, Query()],
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistTurnoverResponse:
    """Return bounded persisted turnover summaries without entry-set queries."""
    return service.turnover(session, query)


@router.get(
    "/api/v1/blacklist/analytics/requests",
    response_model=BlacklistRequestSeriesResponse,
    responses={503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_blacklist_request_series(
    query: Annotated[BlacklistRequestSeriesQuery, Query()],
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistRequestSeriesResponse:
    """Return the latest successful snapshot requests chronologically."""
    return service.request_series(session, query)


@router.get(
    "/api/v1/blacklist/snapshots",
    response_model=BlacklistSnapshotList,
    responses={503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def list_blacklist_snapshots(
    query: Annotated[BlacklistSnapshotListQuery, Query()],
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistSnapshotList:
    return service.snapshots(session, query)


@router.get(
    "/api/v1/blacklist/snapshots/{snapshot_id}",
    response_model=BlacklistPage,
    responses={404: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_blacklist_snapshot(
    snapshot_id: Annotated[int, Path(gt=0)],
    query: Annotated[BlacklistEntryPageQuery, Query()],
    request: Request,
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistPage | JSONResponse:
    result = service.snapshot(session, snapshot_id, query)
    if result is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="BLACKLIST_SNAPSHOT_NOT_FOUND",
            message="The requested blacklist snapshot does not exist.",
            request_id=request_id_from(request),
        )
    return result


@router.get(
    "/api/v1/blacklist",
    response_model=BlacklistPage,
    responses={404: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
    tags=["blacklist"],
)
def get_latest_blacklist(
    query: Annotated[BlacklistEntryQuery, Query()],
    request: Request,
    session: Annotated[Session, Depends(get_session)],
    service: Annotated[BlacklistReadService, Depends(get_blacklist_read_service)],
) -> BlacklistPage | JSONResponse:
    result = service.latest(session, query)
    if result is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="BLACKLIST_SNAPSHOT_NOT_FOUND",
            message="No successful blacklist snapshot is available.",
            request_id=request_id_from(request),
        )
    return result


async def validation_exception_handler(
    request: Request, _: RequestValidationError
) -> JSONResponse:
    """Return validation failures without exposing implementation details."""
    return error_response(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        code="INVALID_REQUEST",
        message="The request did not satisfy the API contract.",
        request_id=request_id_from(request),
    )


async def application_exception_handler(
    request: Request, error: ApplicationError
) -> JSONResponse:
    """Return safe application and dependency failures."""
    logger.warning(
        "application_request_failed",
        extra={"request_id": request_id_from(request), "error_code": error.code},
    )
    return error_response(
        status_code=error.status_code,
        code=error.code,
        message=error.message,
        request_id=request_id_from(request),
    )


async def unavailable_exception_handler(
    request: Request, error: HistoryUnavailableError
) -> JSONResponse:
    """Hide database error details from callers."""
    log_sanitized_exception(
        logger, "database_request_failed", error, request_id=request_id_from(request)
    )
    return error_response(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="DATABASE_UNAVAILABLE",
        message="The database is temporarily unavailable.",
        request_id=request_id_from(request),
    )


async def idempotency_conflict_exception_handler(
    request: Request, _: IdempotencyConflictError
) -> JSONResponse:
    """Return a stable conflict when one idempotency key changes meaning."""
    return error_response(
        status_code=status.HTTP_409_CONFLICT,
        code="IDEMPOTENCY_CONFLICT",
        message="The request ID has already been used with different request data.",
        request_id=request_id_from(request),
    )


async def unexpected_exception_handler(
    request: Request, error: Exception
) -> JSONResponse:
    """Log a sanitized traceback and return a stable public failure."""
    request_id = request_id_from(request)
    log_sanitized_exception(
        logger, "unexpected_request_failure", error, request_id=request_id
    )
    return error_response(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="INTERNAL_SERVER_ERROR",
        message="An unexpected internal error occurred.",
        request_id=request_id,
    )
