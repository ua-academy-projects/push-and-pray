from __future__ import annotations

import asyncio
import json
import random
from datetime import UTC, date, datetime
from decimal import Decimal

import httpx
import aio_pika
from aio_pika import DeliveryMode, ExchangeType, Message

from .config import Settings
from .models import HistoryPoint, HistorySeries, Rate


class ProviderError(RuntimeError):
    def __init__(self, provider: str, message: str, status_code: int = 502):
        super().__init__(message)
        self.provider = provider
        self.status_code = status_code


async def _get(client: httpx.AsyncClient, provider: str, url: str, **kwargs) -> httpx.Response:
    for attempt in range(3):
        try:
            response = await client.get(url, **kwargs)
            if response.status_code == 429 or response.status_code >= 500:
                if attempt < 2:
                    delay = float(response.headers.get("Retry-After", 0.3 * (2**attempt)))
                    await asyncio.sleep(delay + random.uniform(0, 0.15))
                    continue
            response.raise_for_status()
            return response
        except (httpx.TimeoutException, httpx.NetworkError, httpx.HTTPStatusError) as exc:
            if attempt < 2 and not isinstance(exc, httpx.HTTPStatusError):
                await asyncio.sleep(0.3 * (2**attempt) + random.uniform(0, 0.15))
                continue
            status = exc.response.status_code if isinstance(exc, httpx.HTTPStatusError) else 502
            raise ProviderError(provider, f"{provider} request failed", status) from exc
    raise ProviderError(provider, f"{provider} request failed")


class CoinGeckoClient:
    def __init__(self, http: httpx.AsyncClient, settings: Settings):
        self.http = http
        self.base_url = settings.coingecko_base_url.rstrip("/")
        self.headers = {"accept": "application/json"}
        if settings.coingecko_api_key:
            self.headers["x-cg-demo-api-key"] = settings.coingecko_api_key

    async def top(self, quote: str = "usd") -> list[Rate]:
        response = await _get(
            self.http,
            "coingecko",
            f"{self.base_url}/coins/markets",
            params={"vs_currency": quote, "order": "market_cap_desc", "per_page": 10, "page": 1, "sparkline": "true", "price_change_percentage": "1h,24h"},
            headers=self.headers,
        )
        requested_at = datetime.now(UTC)
        result = []
        for item in response.json():
            updated = item.get("last_updated") or requested_at.isoformat()
            result.append(Rate(
                instrument_id=f"crypto:{item['id']}:{quote}", kind="crypto",
                base=str(item["symbol"]).upper(), quote=quote.upper(), name=item["name"],
                price=Decimal(str(item["current_price"])),
                change_1h_percent=_decimal(item.get("price_change_percentage_1h_in_currency")),
                change_24h_percent=_decimal(item.get("price_change_percentage_24h")),
                market_cap=_decimal(item.get("market_cap")), rank=item.get("market_cap_rank"),
                sparkline_7d=[Decimal(str(point)) for point in item.get("sparkline_in_7d", {}).get("price", [])] or None,
                source="coingecko", source_timestamp=datetime.fromisoformat(updated.replace("Z", "+00:00")),
                requested_at=requested_at,
            ))
        return result

    async def current(self, coin_id: str, quote: str) -> Rate:
        response = await _get(
            self.http, "coingecko", f"{self.base_url}/coins/markets",
            params={"vs_currency": quote, "ids": coin_id, "sparkline": "true", "price_change_percentage": "1h,24h"},
            headers=self.headers,
        )
        data = response.json()
        if not data:
            raise ProviderError("coingecko", f"Unknown coin: {coin_id}", 404)
        item = data[0]
        requested_at = datetime.now(UTC)
        return Rate(
            instrument_id=f"crypto:{item['id']}:{quote}", kind="crypto",
            base=str(item["symbol"]).upper(), quote=quote.upper(), name=item["name"],
            price=Decimal(str(item["current_price"])),
            change_1h_percent=_decimal(item.get("price_change_percentage_1h_in_currency")),
            change_24h_percent=_decimal(item.get("price_change_percentage_24h")),
            market_cap=_decimal(item.get("market_cap")), rank=item.get("market_cap_rank"),
            sparkline_7d=[Decimal(str(point)) for point in item.get("sparkline_in_7d", {}).get("price", [])] or None,
            source="coingecko", source_timestamp=datetime.fromisoformat(item["last_updated"].replace("Z", "+00:00")),
            requested_at=requested_at,
        )

    async def history(self, coin_id: str, quote: str, start: date, end: date) -> HistorySeries:
        # CoinGecko interprets `days` as lookback duration, not an inclusive
        # count of calendar dates. One year must therefore remain 365 days.
        days = max(1, min(365, (end - start).days))
        params = {"vs_currency": quote, "days": days, "precision": "full"}
        if days > 90:
            params["interval"] = "daily"
        elif days > 1:
            params["interval"] = "hourly"
        # For one day, omit interval so CoinGecko returns its automatic
        # 5-minute granularity. Historical 5-minute data is not available
        # for a full year from this provider.
        response = await _get(
            self.http, "coingecko", f"{self.base_url}/coins/{coin_id}/market_chart",
            params=params,
            headers=self.headers,
        )
        points = [HistoryPoint(timestamp=datetime.fromtimestamp(ts / 1000, UTC), value=Decimal(str(value))) for ts, value in response.json().get("prices", [])]
        return HistorySeries(instrument_id=f"crypto:{coin_id}:{quote}", source="coingecko", points=points)

    async def market_cap_history(self, coin_id: str, quote: str, days: int) -> list[HistoryPoint]:
        params = {"vs_currency": quote, "days": max(1, min(365, days)), "precision": "full"}
        if days > 90:
            params["interval"] = "daily"
        elif days > 1:
            params["interval"] = "hourly"
        response = await _get(self.http, "coingecko", f"{self.base_url}/coins/{coin_id}/market_chart", params=params, headers=self.headers)
        return [HistoryPoint(timestamp=datetime.fromtimestamp(ts / 1000, UTC), value=Decimal(str(value))) for ts, value in response.json().get("market_caps", [])]


class FrankfurterClient:
    def __init__(self, http: httpx.AsyncClient, settings: Settings):
        self.http = http
        self.base_url = settings.frankfurter_base_url.rstrip("/")

    async def current(self, base: str, quote: str) -> Rate:
        response = await _get(self.http, "frankfurter", f"{self.base_url}/rates", params={"base": base, "quotes": quote})
        rows = response.json()
        if not rows:
            raise ProviderError("frankfurter", f"Unknown pair: {base}/{quote}", 404)
        row = rows[-1]
        stamp = datetime.fromisoformat(row["date"]).replace(tzinfo=UTC)
        return Rate(
            instrument_id=f"fiat:{base}:{quote}", kind="fiat", base=base, quote=quote,
            name=f"{base}/{quote}", price=Decimal(str(row["rate"])), source="frankfurter",
            source_timestamp=stamp, requested_at=datetime.now(UTC),
        )

    async def history(self, base: str, quote: str, start: date, end: date) -> HistorySeries:
        response = await _get(
            self.http, "frankfurter", f"{self.base_url}/rates",
            params={"base": base, "quotes": quote, "from": start.isoformat(), "to": end.isoformat()},
        )
        points = [HistoryPoint(timestamp=datetime.fromisoformat(row["date"]).replace(tzinfo=UTC), value=Decimal(str(row["rate"]))) for row in response.json()]
        return HistorySeries(instrument_id=f"fiat:{base}:{quote}", source="frankfurter", points=points)


class ObservationPublisher:
    def __init__(self, settings: Settings):
        self.url = settings.rabbitmq_url
        self.exchange_name = settings.rabbitmq_events_exchange
        self.queue_name = settings.rabbitmq_observations_queue
        self.routing_key = settings.rabbitmq_observation_routing_key
        self.connection = None
        self.channel = None
        self.exchange = None
        self._connect_lock = asyncio.Lock()

    @property
    def connected(self) -> bool:
        return bool(
            self.connection
            and not self.connection.is_closed
            and self.channel
            and not self.channel.is_closed
            and self.exchange
        )

    async def connect(self) -> None:
        async with self._connect_lock:
            if self.connected:
                return
            try:
                self.connection = await aio_pika.connect_robust(self.url, timeout=3)
                self.channel = await self.connection.channel(publisher_confirms=True)
                self.exchange = await self.channel.declare_exchange(self.exchange_name, ExchangeType.DIRECT, durable=True)
                dead_letter_exchange = await self.channel.declare_exchange(f"{self.exchange_name}.dlx", ExchangeType.DIRECT, durable=True)
                dead_letter_queue = await self.channel.declare_queue(f"{self.queue_name}.dlq", durable=True)
                await dead_letter_queue.bind(dead_letter_exchange, self.queue_name)
                queue = await self.channel.declare_queue(
                    self.queue_name,
                    durable=True,
                    arguments={
                        "x-dead-letter-exchange": f"{self.exchange_name}.dlx",
                        "x-dead-letter-routing-key": self.queue_name,
                    },
                )
                await queue.bind(self.exchange, self.routing_key)
            except Exception:
                await self.close()
                raise

    async def publish(self, observation: dict, request_id: str, idempotency_key: str) -> None:
        if not self.connected:
            await self.connect()
        body = json.dumps({
            "event_id": idempotency_key,
            "event_type": "rate.observation.collected",
            "schema_version": 1,
            "request_id": request_id,
            "idempotency_key": idempotency_key,
            "observation": observation,
        }, separators=(",", ":"), ensure_ascii=False).encode()
        await self.exchange.publish(
            Message(
                body,
                content_type="application/json",
                delivery_mode=DeliveryMode.PERSISTENT,
                message_id=idempotency_key,
                correlation_id=request_id,
            ),
            routing_key=self.routing_key,
            mandatory=True,
        )

    async def close(self) -> None:
        if self.connection:
            await self.connection.close()
        self.connection = None
        self.channel = None
        self.exchange = None


class FetchCommandConsumer:
    def __init__(self, settings: Settings, handler):
        self.url = settings.rabbitmq_url
        self.exchange_name = settings.rabbitmq_commands_exchange
        self.queue_name = settings.rabbitmq_commands_queue
        self.routing_key = settings.rabbitmq_command_routing_key
        self.handler = handler
        self.connection = None
        self.channel = None
        self.ready = False

    async def run(self) -> None:
        while True:
            try:
                await self._consume()
            except asyncio.CancelledError:
                raise
            except Exception:
                self.ready = False
                await self.close()
                await asyncio.sleep(2)

    async def _consume(self) -> None:
        self.connection = await aio_pika.connect_robust(self.url, timeout=5)
        self.channel = await self.connection.channel()
        await self.channel.set_qos(prefetch_count=2)
        exchange = await self.channel.declare_exchange(self.exchange_name, ExchangeType.DIRECT, durable=True)
        dlx = await self.channel.declare_exchange(f"{self.exchange_name}.dlx", ExchangeType.DIRECT, durable=True)
        dlq = await self.channel.declare_queue(f"{self.queue_name}.dlq", durable=True)
        await dlq.bind(dlx, self.queue_name)
        queue = await self.channel.declare_queue(
            self.queue_name,
            durable=True,
            arguments={
                "x-dead-letter-exchange": f"{self.exchange_name}.dlx",
                "x-dead-letter-routing-key": self.queue_name,
            },
        )
        await queue.bind(exchange, self.routing_key)
        self.ready = True
        async with queue.iterator() as iterator:
            async for message in iterator:
                try:
                    payload = json.loads(message.body)
                    if payload.get("command_type") != "rates.backfill.requested":
                        await message.reject(requeue=False)
                        continue
                    await self.handler(payload)
                    await message.ack()
                except (ValueError, TypeError, json.JSONDecodeError):
                    await message.reject(requeue=False)
                except Exception:
                    await message.reject(requeue=not message.redelivered)

    async def close(self) -> None:
        self.ready = False
        if self.connection:
            await self.connection.close()
        self.connection = None
        self.channel = None


def _decimal(value) -> Decimal | None:
    return None if value is None else Decimal(str(value))
