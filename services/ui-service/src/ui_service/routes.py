"""Server-rendered routes for the Aegis UI."""

import logging
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from time import monotonic
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Form, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.templating import Jinja2Templates

from ui_service.application_client import (
    ApplicationClient,
    ApplicationClientError,
    get_application_client,
)
from ui_service.config import Settings
from ui_service.schemas import (
    BlacklistAnalytics,
    BlacklistPage,
    BlacklistPollStatus,
    BlacklistStatus,
    BlacklistTurnover,
    CheckResult,
    HistoryPage,
)
from ui_service.security_logging import log_sanitized_exception
from ui_service.theme.http import (
    ThemeContext,
    get_theme_context,
    get_theme_service,
    get_theme_settings,
)
from ui_service.theme.service import ThemeService, ThemeUnavailableError

router = APIRouter()
logger = logging.getLogger(__name__)
templates = Jinja2Templates(directory=Path(__file__).parent / "templates")
BLACKLIST_PAGE_SIZE = 100
BLACKLIST_CHURN_PAIR_LIMIT = 10
BLACKLIST_SCRIPT = (Path(__file__).parent / "static" / "blacklist.js").read_text(
    encoding="utf-8"
)
BLACKLIST_STYLE = (Path(__file__).parent / "static" / "blacklist.css").read_text(
    encoding="utf-8"
)
BASE_STYLE = (Path(__file__).parent / "static" / "style.css").read_text(
    encoding="utf-8"
)


class TurnoverRange(StrEnum):
    seven_days = "7"
    thirty_days = "30"
    ninety_days = "90"
    all = "all"


def request_id_for(request: Request) -> str:
    established = getattr(request.state, "request_id", None)
    if established is not None:
        return str(established)
    supplied = request.headers.get("X-Request-ID")
    if supplied is not None:
        try:
            return str(UUID(supplied))
        except ValueError:
            pass
    return str(uuid4())


async def request_logging_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    request_id = request_id_for(request)
    request.state.request_id = request_id
    started = monotonic()
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    logger.info(
        "http_request_completed",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "duration_ms": round((monotonic() - started) * 1000, 2),
        },
    )
    return response


async def load_history(
    application_client: ApplicationClient, request_id: str
) -> tuple[HistoryPage | None, str | None]:
    try:
        return await application_client.recent_history(request_id=request_id), None
    except ApplicationClientError as error:
        return None, str(error)


def render_page(
    request: Request,
    *,
    request_id: str,
    theme_context: ThemeContext,
    settings: Settings,
    ip_address: str = "",
    max_age_days: str = "30",
    result: CheckResult | None = None,
    error: str | None = None,
    history: HistoryPage | None = None,
    history_error: str | None = None,
) -> HTMLResponse:
    return render_template(
        request,
        name="index.html",
        request_id=request_id,
        theme_context=theme_context,
        settings=settings,
        context={
            "ip_address": ip_address,
            "max_age_days": max_age_days,
            "result": result,
            "error": error,
            "history": history,
            "history_error": history_error,
        },
    )


def render_template(
    request: Request,
    *,
    name: str,
    request_id: str,
    theme_context: ThemeContext,
    settings: Settings,
    context: dict[str, object],
) -> HTMLResponse:
    """Inject UI-owned theme state into every Jinja response."""
    response = templates.TemplateResponse(
        request=request,
        name=name,
        context={
            **context,
            "theme": theme_context.theme,
            "theme_context": theme_context,
        },
    )
    response.headers["X-Request-ID"] = request_id
    theme_context.apply_cookie(response, request, settings)
    return response


@router.get("/health/live", tags=["health"])
async def liveness() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/static/style.css", include_in_schema=False)
async def base_style() -> Response:
    return Response(content=BASE_STYLE, media_type="text/css")


@router.get("/static/blacklist.js", include_in_schema=False)
async def blacklist_script() -> Response:
    return Response(content=BLACKLIST_SCRIPT, media_type="text/javascript")


@router.get("/static/blacklist.css", include_in_schema=False)
async def blacklist_style() -> Response:
    return Response(content=BLACKLIST_STYLE, media_type="text/css")


@router.get("/health/ready", tags=["health"], response_model=None)
async def readiness(
    request: Request,
    application_client: Annotated[ApplicationClient, Depends(get_application_client)],
    theme_service: Annotated[ThemeService, Depends(get_theme_service)],
) -> dict[str, str] | JSONResponse:
    request_id = request_id_for(request)
    try:
        await application_client.ready(request_id=request_id)
        await theme_service.ready()
    except ApplicationClientError, ThemeUnavailableError:
        response = JSONResponse(status_code=503, content={"status": "not ready"})
    else:
        response = JSONResponse(content={"status": "ready"})
    response.headers["X-Request-ID"] = request_id
    return response


@router.get("/", response_class=HTMLResponse, include_in_schema=False)
async def index(
    request: Request,
    application_client: Annotated[ApplicationClient, Depends(get_application_client)],
    theme_context: Annotated[ThemeContext, Depends(get_theme_context)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
) -> HTMLResponse:
    request_id = request_id_for(request)
    history, history_error = await load_history(application_client, request_id)
    return render_page(
        request,
        request_id=request_id,
        theme_context=theme_context,
        settings=settings,
        history=history,
        history_error=history_error,
    )


@router.get("/blacklist", response_class=HTMLResponse, include_in_schema=False)
async def blacklist(
    request: Request,
    application_client: Annotated[ApplicationClient, Depends(get_application_client)],
    theme_context: Annotated[ThemeContext, Depends(get_theme_context)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
    page: Annotated[int, Query(ge=1)] = 1,
    range_days: TurnoverRange = TurnoverRange.thirty_days,
) -> HTMLResponse:
    request_id = request_id_for(request)
    status_result: BlacklistStatus | None = None
    blacklist_page: BlacklistPage | None = None
    analytics: BlacklistAnalytics | None = None
    turnover: BlacklistTurnover | None = None
    error: str | None = None
    analytics_error: str | None = None
    turnover_error: str | None = None

    try:
        status_result = await application_client.blacklist_status(request_id=request_id)
    except ApplicationClientError as application_error:
        error = str(application_error)

    if status_result is not None and status_result.state != "empty":
        try:
            blacklist_page = await application_client.blacklist(
                limit=BLACKLIST_PAGE_SIZE,
                offset=(page - 1) * BLACKLIST_PAGE_SIZE,
                request_id=request_id,
            )
        except ApplicationClientError as application_error:
            error = str(application_error)
        try:
            analytics = await application_client.blacklist_analytics(
                pair_limit=BLACKLIST_CHURN_PAIR_LIMIT,
                request_id=request_id,
            )
        except ApplicationClientError:
            analytics_error = "Snapshot analytics are temporarily unavailable."
        try:
            if range_days is TurnoverRange.all:
                turnover = await application_client.blacklist_turnover(
                    period="all",
                    interval="auto",
                    request_id=request_id,
                )
            else:
                range_to = datetime.now(UTC).replace(
                    hour=0, minute=0, second=0, microsecond=0
                ) + timedelta(days=1)
                turnover = await application_client.blacklist_turnover(
                    from_=range_to - timedelta(days=int(range_days)),
                    to=range_to,
                    interval="auto",
                    request_id=request_id,
                )
        except ApplicationClientError:
            turnover_error = "Turnover history is temporarily unavailable."

    return render_template(
        request,
        name="blacklist.html",
        request_id=request_id,
        theme_context=theme_context,
        settings=settings,
        context={
            "status": status_result,
            "blacklist": blacklist_page,
            "analytics": analytics,
            "turnover": turnover,
            "turnover_points": (
                turnover.model_dump(mode="json", by_alias=True)["points"]
                if turnover is not None
                else []
            ),
            "error": error,
            "analytics_error": analytics_error,
            "turnover_error": turnover_error,
            "page": page,
            "range_days": range_days,
        },
    )


@router.get(
    "/blacklist/status",
    response_model=BlacklistPollStatus,
    responses={503: {"description": "History Service is unavailable"}},
    include_in_schema=False,
)
async def blacklist_status(
    request: Request,
    application_client: Annotated[ApplicationClient, Depends(get_application_client)],
) -> BlacklistPollStatus | JSONResponse:
    request_id = request_id_for(request)
    try:
        status_result = await application_client.blacklist_status(request_id=request_id)
    except ApplicationClientError:
        response = JSONResponse(
            status_code=503,
            content={"error": "Blacklist status is temporarily unavailable."},
        )
    else:
        response = JSONResponse(
            content=BlacklistPollStatus(
                state=status_result.state,
                latest_snapshot_id=status_result.latest_snapshot_id,
                data_stale=status_result.data_stale,
            ).model_dump(mode="json")
        )
    response.headers["X-Request-ID"] = request_id
    return response


@router.post("/", response_class=HTMLResponse, include_in_schema=False)
async def submit_check(
    request: Request,
    application_client: Annotated[ApplicationClient, Depends(get_application_client)],
    theme_context: Annotated[ThemeContext, Depends(get_theme_context)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
    ip_address: Annotated[str, Form()] = "",
    max_age_days: Annotated[str, Form()] = "30",
) -> HTMLResponse:
    request_id = request_id_for(request)
    result = None
    error = None

    if not ip_address.strip():
        error = "Enter an IPv4 or IPv6 address."
    else:
        try:
            parsed_max_age = int(max_age_days)
            if not 1 <= parsed_max_age <= 365:
                raise ValueError
        except ValueError:
            error = "Max age must be a whole number between 1 and 365."
        else:
            try:
                result = await application_client.check(
                    ip_address=ip_address.strip(),
                    max_age_days=parsed_max_age,
                    request_id=request_id,
                )
            except ApplicationClientError as application_error:
                error = str(application_error)

    history, history_error = await load_history(application_client, request_id)
    return render_page(
        request,
        request_id=request_id,
        theme_context=theme_context,
        settings=settings,
        ip_address=ip_address,
        max_age_days=max_age_days,
        result=result,
        error=error,
        history=history,
        history_error=history_error,
    )


async def unexpected_exception_handler(
    request: Request, error: Exception
) -> JSONResponse:
    """Return a request-correlated response without exposing exception details."""
    request_id = request_id_for(request)
    log_sanitized_exception(
        logger, "unexpected_request_failure", error, request_id=request_id
    )
    response = JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "An unexpected internal error occurred.",
                "request_id": request_id,
            }
        },
    )
    response.headers["X-Request-ID"] = request_id
    return response
