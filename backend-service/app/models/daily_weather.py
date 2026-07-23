import enum
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class AverageTemperatureMethod(str, enum.Enum):
    """Which calculation produced average_temperature / average_apparent_temperature for a
    given day -- reported so a response never silently mixes methods across days."""

    HOURLY = "hourly"
    MIN_MAX_FALLBACK = "min_max_fallback"


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

    # Derived at persist time from that date's hourly rows when enough exist, else a
    # (min+max)/2 fallback -- see persistence_service._compute_daily_averages(). Humidity/
    # wind/cloud cover have no natural fallback source (no daily min/max column for them),
    # so they stay NULL on a day with no hourly data at all.
    average_temperature: Mapped[float] = mapped_column(Float, nullable=False)
    average_temperature_method: Mapped[AverageTemperatureMethod] = mapped_column(
        SAEnum(
            AverageTemperatureMethod,
            native_enum=False,
            length=20,
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        nullable=False,
    )
    average_apparent_temperature: Mapped[float] = mapped_column(Float, nullable=False)
    average_humidity: Mapped[float | None] = mapped_column(Float, nullable=True)
    average_wind_speed: Mapped[float | None] = mapped_column(Float, nullable=True)
    average_cloud_cover: Mapped[float | None] = mapped_column(Float, nullable=True)

    source: Mapped[str] = mapped_column(String(50), nullable=False, default="Open-Meteo")
    synchronized_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
