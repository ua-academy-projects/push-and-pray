from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ObservationCreate(BaseModel):
    instrument_code: str = Field(min_length=1, max_length=80)
    instrument_name: str = Field(min_length=1, max_length=180)
    category: Literal["crude_oil", "gasoline"]
    price: Decimal = Field(gt=0)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    unit: str = Field(min_length=1, max_length=80)
    source: str = Field(min_length=1, max_length=80)
    source_series_id: str = Field(min_length=1, max_length=160)
    source_period: date
    source_observed_at: datetime
    scheduled_for: datetime
    fetched_at: datetime
    source_url: str = Field(min_length=1)
    raw_data: dict

    @field_validator("source_observed_at", "scheduled_for", "fetched_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("timestamp must include a timezone")
        return value


class ObservationBatch(BaseModel):
    observations: list[ObservationCreate] = Field(min_length=1, max_length=50)


class ObservationEvent(ObservationBatch):
    schema_version: Literal[1]


class ObservationRead(ObservationCreate):
    id: UUID
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class BatchResult(BaseModel):
    inserted: int
    duplicates: int


class InstrumentRead(BaseModel):
    code: str
    name: str
    category: str
    currency: str
    unit: str
