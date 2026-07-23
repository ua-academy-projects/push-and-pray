from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class DailyWeather(Base):
    """One row per location per calendar day. Preserved indefinitely (never deleted)."""

    __tablename__ = "daily_weather"
    __table_args__ = (UniqueConstraint("location_id", "weather_date", name="uq_daily_weather_location_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("locations.id", ondelete="CASCADE"), nullable=False)
    weather_date: Mapped[date] = mapped_column(Date, nullable=False)
    weather_code: Mapped[int] = mapped_column(Integer, nullable=False)
    temperature_max: Mapped[float] = mapped_column(Float, nullable=False)
    temperature_min: Mapped[float] = mapped_column(Float, nullable=False)
    apparent_temperature_max: Mapped[float] = mapped_column(Float, nullable=False)
    apparent_temperature_min: Mapped[float] = mapped_column(Float, nullable=False)
    sunrise: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    sunset: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    precipitation_sum: Mapped[float] = mapped_column(Float, nullable=False)
    rain_sum: Mapped[float] = mapped_column(Float, nullable=False)
    snowfall_sum: Mapped[float] = mapped_column(Float, nullable=False)
    precipitation_hours: Mapped[float] = mapped_column(Float, nullable=False)
    wind_speed_max: Mapped[float] = mapped_column(Float, nullable=False)
    wind_gusts_max: Mapped[float] = mapped_column(Float, nullable=False)
    source: Mapped[str] = mapped_column(String(50), nullable=False, default="Open-Meteo")
    synchronized_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
