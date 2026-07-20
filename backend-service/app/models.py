from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer


class Rate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    instrument_id: str
    kind: Literal["crypto", "fiat"]
    base: str
    quote: str
    name: str
    price: Decimal
    change_1h_percent: Decimal | None = None
    change_24h_percent: Decimal | None = None
    market_cap: Decimal | None = None
    rank: int | None = None
    sparkline_7d: list[Decimal] | None = None
    source: Literal["coingecko", "frankfurter"]
    source_timestamp: datetime
    requested_at: datetime
    stale: bool = False
    persistence_status: Literal["saved", "failed", "skipped"] = "skipped"

    @field_serializer("price", "change_1h_percent", "change_24h_percent", "market_cap")
    def serialize_decimal(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, "f")

    @field_serializer("sparkline_7d")
    def serialize_sparkline(self, value: list[Decimal] | None) -> list[str] | None:
        return None if value is None else [format(point, "f") for point in value]


class HistoryPoint(BaseModel):
    timestamp: datetime
    value: Decimal

    @field_serializer("value")
    def serialize_value(self, value: Decimal) -> str:
        return format(value, "f")


class HistorySeries(BaseModel):
    instrument_id: str
    source: str
    points: list[HistoryPoint]


class MarketTile(BaseModel):
    instrument_id: str
    name: str
    symbol: str
    market_cap: Decimal
    change_percent: Decimal
    period: str
    source: str = "coingecko"
    source_timestamp: datetime

    @field_serializer("market_cap", "change_percent")
    def serialize_market_decimal(self, value: Decimal) -> str:
        return format(value, "f")


class RefreshRequest(BaseModel):
    instruments: list[str] = Field(min_length=1, max_length=20)


class BackfillRequest(BaseModel):
    instruments: list[str] = Field(min_length=1, max_length=20)
    from_date: date
    to_date: date
