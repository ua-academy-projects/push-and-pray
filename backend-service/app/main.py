import asyncio
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .clients import ApiFetcherClient, CoinGeckoClient, FrankfurterClient, ObservationPublisher, ProviderError
from .config import get_settings
from .models import BackfillRequest, RefreshRequest
from .services import FIAT_BASES, RateService

settings = get_settings()
logging.basicConfig(level=settings.log_level, format="%(message)s")
logger = logging.getLogger("rateboard")


def seconds_until_boundary(now: float, interval: int) -> float:
    """Return the delay to the next wall-clock interval boundary."""
    remainder = now % interval
    return 0.0 if remainder < 0.05 else interval - remainder


async def collector_loop(app: FastAPI):
    """Collect fresh observations on wall-clock boundaries without blocking API traffic."""
    interval = max(60, settings.collector_interval_seconds)
    while True:
        # For the default 300 seconds, run at :00, :05, :10, ... instead of
        # counting five minutes from the Backend startup time.
        await asyncio.sleep(seconds_until_boundary(time.time(), interval))
        cycle_timestamp = datetime.now(UTC).replace(second=0, microsecond=0)
        started = time.monotonic()
        request_id = str(uuid.uuid4())
        saved = 0
        failed = 0
        for item in app.state.rates.catalog():
            try:
                rate = await app.state.rates.current(item["instrument_id"], refresh=True)
                rate = rate.model_copy(update={"requested_at": cycle_timestamp})
                if await app.state.api_fetcher.save(rate, request_id) in ("queued", "saved"):
                    saved += 1
                else:
                    failed += 1
            except Exception as exc:
                failed += 1
                logger.warning(
                    '{"service":"backend","event":"collector_error","request_id":"%s","instrument_id":"%s","error_type":"%s"}',
                    request_id, item["instrument_id"], type(exc).__name__,
                )
        logger.info(
            '{"service":"backend","event":"collector_cycle","request_id":"%s","saved":%d,"failed":%d,"latency_ms":%.2f}',
            request_id, saved, failed, (time.monotonic() - started) * 1000,
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    http = httpx.AsyncClient(timeout=httpx.Timeout(10, connect=5))
    publisher = ObservationPublisher(settings) if settings.rabbitmq_enabled else None
    if publisher:
        await publisher.connect()
    api_fetcher = ApiFetcherClient(http, settings, publisher)
    app.state.api_fetcher = api_fetcher
    app.state.rates = RateService(CoinGeckoClient(http, settings), FrankfurterClient(http, settings), api_fetcher)
    collector_task = asyncio.create_task(collector_loop(app)) if settings.collector_enabled else None
    yield
    if collector_task:
        collector_task.cancel()
        try:
            await collector_task
        except asyncio.CancelledError:
            pass
    if publisher:
        await publisher.close()
    await http.aclose()


app = FastAPI(title="Rateboard Backend", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=[settings.ui_origin], allow_methods=["GET", "POST"], allow_headers=["Content-Type", "X-Request-ID"])


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request.state.request_id = request_id
    started = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    logger.info('{"service":"backend","request_id":"%s","route":"%s","status":%s,"latency_ms":%.2f}', request_id, request.url.path, response.status_code, (time.perf_counter() - started) * 1000)
    return response


@app.exception_handler(ProviderError)
async def provider_error(request: Request, exc: ProviderError):
    code = "UPSTREAM_RATE_LIMITED" if exc.status_code == 429 else "UPSTREAM_ERROR"
    status = 429 if exc.status_code == 429 else (404 if exc.status_code == 404 else 502)
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": str(exc), "request_id": request.state.request_id, "retry_after_seconds": 30 if status == 429 else None}})


@app.get("/health/live")
async def live():
    return {"status": "ok", "service": "backend"}


@app.get("/health/ready")
async def ready(request: Request):
    api_fetcher_ready = await request.app.state.api_fetcher.ready()
    return JSONResponse(status_code=200 if api_fetcher_ready else 503, content={"status": "ready" if api_fetcher_ready else "degraded", "api_fetcher": api_fetcher_ready})


@app.get("/api/v1/instruments")
async def instruments(request: Request):
    return {"items": request.app.state.rates.catalog()}


@app.get("/api/v1/market-map")
async def market_map(request: Request, period: str = "1d"):
    try:
        return {"period": period, "items": await request.app.state.rates.market_map(period)}
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc


async def persist(rates, request: Request):
    results = await asyncio.gather(*(request.app.state.api_fetcher.save(rate, request.state.request_id) for rate in rates))
    return [rate.model_copy(update={"persistence_status": status}) for rate, status in zip(rates, results)]


@app.get("/api/v1/overview")
async def overview(request: Request, quote: str = "usd", fiat_quote: str = "UAH"):
    if not quote.isalpha() or not fiat_quote.isalpha():
        raise HTTPException(400, "Invalid quote currency")
    service: RateService = request.app.state.rates
    crypto_task = service.top(quote.lower())
    fiat_tasks = [service.current(f"fiat:{base}:{fiat_quote.upper()}") for base in FIAT_BASES]
    crypto, *fiat = await asyncio.gather(crypto_task, *fiat_tasks)
    return {"primary": crypto[0], "crypto": crypto, "fiat": fiat}


def split_ids(raw: str, maximum: int) -> list[str]:
    ids = [item.strip() for item in raw.split(",") if item.strip()]
    if not ids or len(ids) > maximum:
        raise HTTPException(400, f"Provide between 1 and {maximum} instruments")
    return ids


@app.get("/api/v1/rates/current")
async def current(request: Request, instruments: str, refresh: bool = False):
    try:
        rates = await request.app.state.rates.current_many(split_ids(instruments, 10), refresh)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    if refresh:
        rates = await persist(rates, request)
    return {"items": rates}


@app.post("/api/v1/rates/refresh")
async def refresh(payload: RefreshRequest, request: Request):
    try:
        rates = await request.app.state.rates.current_many(payload.instruments, True)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return {"items": await persist(rates, request)}


@app.post("/api/v1/rates/backfill")
async def backfill(payload: BackfillRequest, request: Request):
    start, end = payload.from_date, payload.to_date
    if start > end or (end - start).days > 366:
        raise HTTPException(400, "Backfill range must be ordered and no longer than one year")
    results = []
    for instrument_id in payload.instruments:
        try:
            fetched, saved = await request.app.state.rates.backfill(instrument_id, start, end, request.state.request_id)
            result = {"instrument_id": instrument_id, "fetched": fetched}
            if settings.rabbitmq_enabled:
                result.update({"queued": saved, "persistence_status": "queued"})
            else:
                result.update({"inserted": saved, "duplicates": fetched - saved, "persistence_status": "saved"})
            results.append(result)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(503, f"API Fetcher failed while saving {instrument_id}") from exc
    return {"from": start, "to": end, "results": results}


@app.get("/api/v1/rates/history")
async def rate_history(request: Request, instruments: str, from_: datetime = Query(alias="from"), to: datetime = Query(alias="to"), step: str = "5m", mode: str = "price"):
    ids = split_ids(instruments, 5)
    if from_ > to or (to - from_).days > 366:
        raise HTTPException(400, "Date range must be ordered and no longer than one year")
    if mode not in ("price", "percent"):
        raise HTTPException(400, "Mode must be price or percent")
    if step not in ("5m", "30m", "1h", "4h", "1d"):
        raise HTTPException(400, "Unsupported history step")
    try:
        series = await request.app.state.api_fetcher.series(ids, from_, to, step)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "API Fetcher unavailable") from exc
    return {"mode": mode, "series": series}


@app.get("/api/v1/requests/history")
async def request_history(request: Request, instrument_id: str | None = None, limit: int = Query(50, ge=1, le=100), cursor: str | None = None):
    params = {"limit": limit}
    if instrument_id:
        params["instrument_id"] = instrument_id
    if cursor:
        params["cursor"] = cursor
    try:
        return await request.app.state.api_fetcher.list(params)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "API Fetcher unavailable") from exc


@app.get("/api/v1/rates/stored-current")
async def stored_current(request: Request, instruments: str):
    """Return the latest persisted sample for each instrument without provider calls."""
    ids = split_ids(instruments, 10)
    try:
        responses = await asyncio.gather(*(
            request.app.state.api_fetcher.list({"instrument_id": instrument_id, "limit": 1})
            for instrument_id in ids
        ))
    except httpx.HTTPError as exc:
        raise HTTPException(503, "API Fetcher unavailable") from exc
    items = [response["items"][0] for response in responses if response.get("items")]
    return {"items": items, "source": "postgresql"}
