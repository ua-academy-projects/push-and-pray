import asyncio
import time
from datetime import UTC, date, datetime
from decimal import Decimal

from .clients import CoinGeckoClient, FrankfurterClient, HistoryClient
from .models import HistorySeries, MarketTile, Rate

FIAT_BASES = ("USD", "EUR", "GBP", "PLN", "CHF", "CAD", "AUD", "JPY", "CNY", "CZK")
KNOWN_CRYPTO = {
    "bitcoin": ("BTC", "Bitcoin"), "ethereum": ("ETH", "Ethereum"),
    "tether": ("USDT", "Tether"), "binancecoin": ("BNB", "BNB"),
    "solana": ("SOL", "Solana"), "usd-coin": ("USDC", "USDC"),
    "ripple": ("XRP", "XRP"), "dogecoin": ("DOGE", "Dogecoin"),
    "cardano": ("ADA", "Cardano"), "tron": ("TRX", "TRON"),
}
MARKET_PERIODS = {"1h": (1, 3600), "4h": (1, 4 * 3600), "1d": (1, 86400), "7d": (7, 7 * 86400), "30d": (30, 30 * 86400), "1y": (365, 365 * 86400)}


class TTLCache:
    def __init__(self):
        self._items: dict[str, tuple[float, object]] = {}

    def get(self, key: str):
        item = self._items.get(key)
        if item and item[0] > time.monotonic():
            return item[1]
        return None

    def set(self, key: str, value, ttl: int):
        self._items[key] = (time.monotonic() + ttl, value)


class RateService:
    def __init__(self, crypto: CoinGeckoClient, fiat: FrankfurterClient, history: HistoryClient):
        self.crypto = crypto
        self.fiat = fiat
        self.history_client = history
        self.cache = TTLCache()

    @staticmethod
    def parse(instrument_id: str) -> tuple[str, str, str]:
        parts = instrument_id.split(":")
        if len(parts) != 3 or parts[0] not in ("crypto", "fiat"):
            raise ValueError(f"Invalid instrument: {instrument_id}")
        kind, base, quote = parts
        if kind == "crypto":
            if not base or not quote.isalpha():
                raise ValueError(f"Invalid instrument: {instrument_id}")
            return kind, base.lower(), quote.lower()
        if not (base.isalpha() and quote.isalpha() and len(base) == 3 and len(quote) == 3):
            raise ValueError(f"Invalid instrument: {instrument_id}")
        return kind, base.upper(), quote.upper()

    def catalog(self) -> list[dict]:
        crypto = [{"instrument_id": f"crypto:{coin_id}:usd", "kind": "crypto", "base": symbol, "quote": "USD", "name": name} for coin_id, (symbol, name) in KNOWN_CRYPTO.items()]
        fiat = [{"instrument_id": f"fiat:{base}:UAH", "kind": "fiat", "base": base, "quote": "UAH", "name": f"{base}/UAH"} for base in FIAT_BASES]
        return crypto + fiat

    async def top(self, quote: str = "usd", refresh: bool = False) -> list[Rate]:
        key = f"top:{quote}"
        if not refresh and (cached := self.cache.get(key)):
            return cached
        rates = await self.crypto.top(quote)
        self.cache.set(key, rates, 60)
        return rates

    async def current(self, instrument_id: str, refresh: bool = False) -> Rate:
        kind, base, quote = self.parse(instrument_id)
        key = f"current:{kind}:{base}:{quote}"
        if not refresh and (cached := self.cache.get(key)):
            return cached.model_copy(update={"persistence_status": "skipped"})
        rate = await (self.crypto.current(base, quote) if kind == "crypto" else self.fiat.current(base, quote))
        self.cache.set(key, rate, 30 if kind == "crypto" else 3600)
        return rate

    async def current_many(self, ids: list[str], refresh: bool = False) -> list[Rate]:
        return list(await asyncio.gather(*(self.current(item, refresh) for item in ids)))

    async def provider_history(self, instrument_id: str, start: date, end: date) -> HistorySeries:
        kind, base, quote = self.parse(instrument_id)
        return await (self.crypto.history(base, quote, start, end) if kind == "crypto" else self.fiat.history(base, quote, start, end))

    async def backfill(self, instrument_id: str, start: date, end: date, request_id: str) -> tuple[int, int]:
        kind, base, quote = self.parse(instrument_id)
        series = await self.provider_history(instrument_id, start, end)
        symbol, name = KNOWN_CRYPTO.get(base, (base.upper(), base.title())) if kind == "crypto" else (base, f"{base}/{quote}")
        rates = [Rate(
            instrument_id=instrument_id, kind=kind, base=symbol, quote=quote.upper(), name=name,
            price=point.value, source=series.source, source_timestamp=point.timestamp,
            requested_at=point.timestamp,
        ) for point in series.points]
        saved = await self.history_client.save_batch(rates, request_id) if rates else 0
        return len(rates), saved

    async def market_map(self, period: str) -> list[MarketTile]:
        if period not in MARKET_PERIODS:
            raise ValueError(f"Unsupported market-map period: {period}")
        key = f"market-map:{period}"
        if cached := self.cache.get(key):
            return cached
        days, seconds = MARKET_PERIODS[period]
        current = await self.top("usd")
        histories = await asyncio.gather(*(self.crypto.market_cap_history(rate.instrument_id.split(":")[1], "usd", days) for rate in current))
        cutoff = datetime.now(UTC).timestamp() - seconds
        tiles = []
        for rate, points in zip(current, histories):
            usable = [point for point in points if point.timestamp.timestamp() >= cutoff]
            baseline = (usable[0] if usable else points[0]) if points else None
            current_cap = rate.market_cap or Decimal("0")
            change = ((current_cap / baseline.value) - Decimal("1")) * Decimal("100") if baseline and baseline.value else Decimal("0")
            tiles.append(MarketTile(
                instrument_id=rate.instrument_id, name=rate.name, symbol=rate.base,
                market_cap=current_cap, change_percent=change, period=period,
                source_timestamp=rate.source_timestamp,
            ))
        self.cache.set(key, tiles, 300)
        return tiles
