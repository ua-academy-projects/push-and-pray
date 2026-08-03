import asyncio
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from .clients import (
    CoinGeckoClient,
    FetchCommandConsumer,
    FrankfurterClient,
    ObservationPublisher,
    ProviderError,
)
from .config import get_settings
from .models import BackfillRequest, RefreshRequest
from .services import RateService

settings = get_settings()
logging.basicConfig(level=settings.log_level, format="%(message)s")
logger = logging.getLogger("rateboard")


def seconds_until_boundary(now: float, interval: int) -> float:
    remainder = now % interval
    return 0.0 if remainder < 0.05 else interval - remainder


def observation_payload(rate, request_id: str) -> tuple[dict, str]:
    payload = rate.model_dump(mode="json", exclude={"stale", "persistence_status", "sparkline_7d"})
    payload["request_id"] = request_id
    key = f"{rate.source}:{rate.instrument_id}:{rate.source_timestamp.isoformat()}:{rate.requested_at.isoformat()}"
    return payload, key


async def publish_rates(app: FastAPI, rates, request_id: str) -> int:
    if not app.state.publisher:
        raise RuntimeError("RabbitMQ publishing is disabled")
    queued = 0
    for rate in rates:
        payload, key = observation_payload(rate, request_id)
        await app.state.publisher.publish(payload, request_id, key)
        queued += 1
    return queued


async def run_backfill(app: FastAPI, payload: dict) -> dict:
    instrument_id = str(payload["instrument_id"])
    start = date.fromisoformat(str(payload["from"])[:10])
    end = date.fromisoformat(str(payload["to"])[:10])
    if start > end or (end - start).days > 365:
        raise ValueError("Backfill range must be ordered and no longer than 365 days")
    request_id = str(payload.get("request_id") or uuid.uuid4())
    rates = await app.state.rates.backfill(instrument_id, start, end)
    queued = await publish_rates(app, rates, request_id)
    logger.info(
        '{"service":"api-fetcher","event":"backfill_queued","request_id":"%s","instrument_id":"%s","queued":%d}',
        request_id, instrument_id, queued,
    )
    return {"instrument_id": instrument_id, "fetched": len(rates), "queued": queued}


async def collector_loop(app: FastAPI):
    interval = max(60, settings.collector_interval_seconds)
    while True:
        await asyncio.sleep(seconds_until_boundary(time.time(), interval))
        cycle_timestamp = datetime.now(UTC).replace(second=0, microsecond=0)
        request_id = str(uuid.uuid4())
        queued = failed = 0
        for item in app.state.rates.catalog():
            try:
                rate = await app.state.rates.current(item["instrument_id"], refresh=True)
                rate = rate.model_copy(update={"requested_at": cycle_timestamp})
                queued += await publish_rates(app, [rate], request_id)
            except Exception as exc:
                failed += 1
                logger.warning(
                    '{"service":"api-fetcher","event":"collector_error","request_id":"%s","instrument_id":"%s","error_type":"%s"}',
                    request_id, item["instrument_id"], type(exc).__name__,
                )
        logger.info(
            '{"service":"api-fetcher","event":"collector_cycle","request_id":"%s","queued":%d,"failed":%d}',
            request_id, queued, failed,
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    http = httpx.AsyncClient(timeout=httpx.Timeout(10, connect=5))
    publisher = ObservationPublisher(settings) if settings.rabbitmq_enabled else None
    if publisher:
        await publisher.connect()
    app.state.publisher = publisher
    app.state.rates = RateService(CoinGeckoClient(http, settings), FrankfurterClient(http, settings))
    command_consumer = FetchCommandConsumer(settings, lambda payload: run_backfill(app, payload)) if settings.rabbitmq_enabled else None
    app.state.command_consumer = command_consumer
    command_task = asyncio.create_task(command_consumer.run()) if command_consumer else None
    collector_task = asyncio.create_task(collector_loop(app)) if settings.collector_enabled else None
    yield
    for task in (collector_task, command_task):
        if task:
            task.cancel()
    for task in (collector_task, command_task):
        if task:
            try:
                await task
            except asyncio.CancelledError:
                pass
    if command_consumer:
        await command_consumer.close()
    if publisher:
        await publisher.close()
    await http.aclose()


app = FastAPI(title="Rateboard API Fetcher", version="2.0.0", lifespan=lifespan)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request.state.request_id = request_id
    started = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    logger.info(
        '{"service":"api-fetcher","request_id":"%s","route":"%s","status":%s,"latency_ms":%.2f}',
        request_id, request.url.path, response.status_code, (time.perf_counter() - started) * 1000,
    )
    return response


@app.exception_handler(ProviderError)
async def provider_error(request: Request, exc: ProviderError):
    code = "UPSTREAM_RATE_LIMITED" if exc.status_code == 429 else "UPSTREAM_ERROR"
    status = 429 if exc.status_code == 429 else (404 if exc.status_code == 404 else 502)
    return JSONResponse(
        status_code=status,
        content={"error": {"code": code, "message": str(exc), "request_id": request.state.request_id}},
    )


def authorize(token: str | None) -> None:
    if token != settings.internal_api_token:
        raise HTTPException(401, "Unauthorized")


@app.get("/health/live")
async def live():
    return {"status": "ok", "service": "api-fetcher"}


@app.get("/health/ready")
async def ready(request: Request):
    publisher_ready = bool(request.app.state.publisher and request.app.state.publisher.connected)
    consumer_ready = bool(request.app.state.command_consumer and request.app.state.command_consumer.ready)
    ready_now = publisher_ready and consumer_ready
    return JSONResponse(
        status_code=200 if ready_now else 503,
        content={
            "status": "ready" if ready_now else "not_ready",
            "rabbitmq_publisher": publisher_ready,
            "rabbitmq_command_consumer": consumer_ready,
        },
    )


@app.post("/internal/v1/collect")
async def collect(payload: RefreshRequest, request: Request, authorization: str | None = Header(default=None)):
    authorize((authorization or "").removeprefix("Bearer "))
    rates = await request.app.state.rates.current_many(payload.instruments, refresh=True)
    queued = await publish_rates(request.app, rates, request.state.request_id)
    return {"queued": queued, "persistence_status": "queued"}


@app.post("/internal/v1/backfill")
async def backfill(payload: BackfillRequest, request: Request, authorization: str | None = Header(default=None)):
    authorize((authorization or "").removeprefix("Bearer "))
    results = []
    for instrument_id in payload.instruments:
        results.append(await run_backfill(request.app, {
            "instrument_id": instrument_id,
            "from": payload.from_date.isoformat(),
            "to": payload.to_date.isoformat(),
            "request_id": request.state.request_id,
        }))
    return {"from": payload.from_date, "to": payload.to_date, "results": results}
