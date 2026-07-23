from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class DailyForecast(Base):
    """One row per location per predicted future day. Unlike `daily_weather`, this table does
    NOT accumulate forever -- a forecast for a given date is fully replaced by a more accurate
    one on every later sync, right up until that date arrives and becomes observed history in
    `daily_weather` instead. Old forecast rows are left in place after their date passes rather
    than actively cleaned up (a harmless "what we predicted" artifact, not something the app
    reconciles) -- see docs/prompts/refactor-3-statistics-api.md."""

    __tablename__ = "daily_forecast"
    __table_args__ = (UniqueConstraint("location_id", "weather_date", name="uq_daily_forecast_location_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("locations.id", ondelete="CASCADE"), nullable=False)
    weather_date: Mapped[date] = mapped_column(Date, nullable=False)
    weather_code: Mapped[int] = mapped_column(Integer, nullable=False)
    temperature_min: Mapped[float] = mapped_column(Float, nullable=False)
    temperature_max: Mapped[float] = mapped_column(Float, nullable=False)
    apparent_temperature_min: Mapped[float] = mapped_column(Float, nullable=False)
    apparent_temperature_max: Mapped[float] = mapped_column(Float, nullable=False)
    precipitation_probability_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(String(50), nullable=False, default="Open-Meteo")
    synchronized_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
