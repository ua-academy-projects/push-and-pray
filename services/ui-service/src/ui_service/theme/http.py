"""HTTP adaptation for anonymous theme sessions."""

from dataclasses import dataclass
from typing import Annotated
from urllib.parse import urlsplit, urlunsplit
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse, Response

from ui_service.config import Settings, get_settings
from ui_service.theme.models import Theme
from ui_service.theme.service import InvalidThemeError, ThemeService

router = APIRouter()


@dataclass(frozen=True)
class ThemeContext:
    session_id: str
    theme: Theme

    @property
    def toggle_theme(self) -> Theme:
        return "light" if self.theme == "dark" else "dark"

    @property
    def icon(self) -> str:
        return "🌙" if self.theme == "dark" else "☀"

    @property
    def toggle_label(self) -> str:
        return f"Switch to {self.toggle_theme} theme"

    def apply_cookie(
        self, response: Response, request: Request, settings: Settings
    ) -> None:
        response.set_cookie(
            key=settings.ui_session_cookie_name,
            value=self.session_id,
            max_age=settings.redis_theme_ttl_seconds,
            httponly=True,
            secure=settings.ui_session_cookie_secure or request.url.scheme == "https",
            samesite="lax",
        )


async def get_theme_service(request: Request) -> ThemeService:
    return request.app.state.theme_service


async def get_theme_settings() -> Settings:
    return get_settings()


async def get_theme_context(
    request: Request,
    service: Annotated[ThemeService, Depends(get_theme_service)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
) -> ThemeContext:
    supplied = request.cookies.get(settings.ui_session_cookie_name)
    try:
        if supplied is None:
            raise ValueError
        parsed = UUID(supplied)
        if parsed.version != 4:
            raise ValueError
        session_id = str(parsed)
    except ValueError:
        session_id = str(uuid4())
    theme = await service.load_theme(session_id)
    return ThemeContext(
        session_id=session_id,
        theme=theme,
    )


@router.get("/theme", tags=["theme"])
async def current_theme(
    context: Annotated[ThemeContext, Depends(get_theme_context)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
    request: Request,
) -> JSONResponse:
    response = JSONResponse({"theme": context.theme})
    context.apply_cookie(response, request, settings)
    return response


@router.post(
    "/theme",
    tags=["theme"],
    responses={
        303: {"description": "Theme saved; redirecting to the referring page."},
        400: {"description": "The submitted theme is invalid."},
    },
)
async def set_theme(
    request: Request,
    context: Annotated[ThemeContext, Depends(get_theme_context)],
    service: Annotated[ThemeService, Depends(get_theme_service)],
    settings: Annotated[Settings, Depends(get_theme_settings)],
    theme: Annotated[str, Form()] = "",
) -> RedirectResponse:
    try:
        await service.save_theme(context.session_id, theme)
    except InvalidThemeError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    response = RedirectResponse(_safe_referer(request), status_code=303)
    context.apply_cookie(response, request, settings)
    return response


def _safe_referer(request: Request) -> str:
    referer = request.headers.get("referer")
    if referer is None:
        return "/"
    parsed = urlsplit(referer)
    if not parsed.scheme and not parsed.netloc:
        return (
            referer
            if parsed.path.startswith("/") and not parsed.path.startswith("//")
            else "/"
        )
    request_url = urlsplit(str(request.base_url))
    if (parsed.scheme, parsed.netloc) != (request_url.scheme, request_url.netloc):
        return "/"
    return urlunsplit(("", "", parsed.path or "/", parsed.query, parsed.fragment))
