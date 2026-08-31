from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


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
    raw_data: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
