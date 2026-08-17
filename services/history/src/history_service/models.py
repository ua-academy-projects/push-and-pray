from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Date,
    DateTime,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base

_JSON_TYPE = JSON().with_variant(JSONB, "postgresql")


class PriceObservation(Base):
    __tablename__ = "price_observations"
    __table_args__ = (
        UniqueConstraint("instrument_code", "scheduled_for", name="uq_instrument_slot"),
        CheckConstraint("price > 0", name="ck_price_positive"),
        CheckConstraint(
            "category IN ('crude_oil', 'gasoline')",
            name="ck_category_known",
        ),
        CheckConstraint("char_length(currency) = 3", name="ck_currency_iso_length"),
        Index("ix_observation_instrument_period", "instrument_code", "source_period"),
        Index("ix_observation_scheduled_for", "scheduled_for"),
        Index("ix_observation_source_observed_at", "source_observed_at"),
        Index(
            "ix_observation_instrument_observed_at",
            "instrument_code",
            "source_observed_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instrument_code: Mapped[str] = mapped_column(String(80), nullable=False)
    instrument_name: Mapped[str] = mapped_column(String(180), nullable=False)
    category: Mapped[str] = mapped_column(String(30), nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    unit: Mapped[str] = mapped_column(String(80), nullable=False)
    source: Mapped[str] = mapped_column(String(80), nullable=False)
    source_series_id: Mapped[str] = mapped_column(String(160), nullable=False)
    source_period: Mapped[date] = mapped_column(Date, nullable=False)
    source_observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    scheduled_for: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    source_url: Mapped[str] = mapped_column(Text, nullable=False)
    raw_data: Mapped[dict] = mapped_column(_JSON_TYPE, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class PriceEvent(Base):
    __tablename__ = "price_events"
    __table_args__ = (
        UniqueConstraint("event_key", name="uq_price_events_event_key"),
        CheckConstraint("schema_version > 0", name="ck_price_events_schema_version_positive"),
        CheckConstraint(
            "status IN ('pending', 'processing', 'processed', 'failed')",
            name="ck_price_events_status_known",
        ),
        CheckConstraint("attempts >= 0", name="ck_price_events_attempts_non_negative"),
        Index(
            "ix_price_events_ready",
            "available_at",
            "created_at",
            postgresql_where=text("status = 'pending'"),
        ),
        Index(
            "ix_price_events_processing_started_at",
            "processing_started_at",
            postgresql_where=text("status = 'processing'"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_key: Mapped[str] = mapped_column(String(200), nullable=False)
    schema_version: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1)
    payload: Mapped[dict] = mapped_column(_JSON_TYPE, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    available_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    processing_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
