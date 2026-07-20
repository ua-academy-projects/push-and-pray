from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    SmallInteger,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class City(Base):
    __tablename__ = "cities"

    id: Mapped[int] = mapped_column(
        BigInteger,
        primary_key=True,
    )

    code: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        unique=True,
    )

    name: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
    )

    country: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        default="Ukraine",
    )

    latitude: Mapped[float] = mapped_column(
        Float,
        nullable=False,
    )

    longitude: Mapped[float] = mapped_column(
        Float,
        nullable=False,
    )

    timezone: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    measurements: Mapped[list["AirQualityMeasurement"]] = relationship(
        back_populates="city",
        cascade="all, delete-orphan",
    )


class AirQualityMeasurement(Base):
    __tablename__ = "air_quality_measurements"

    __table_args__ = (
        UniqueConstraint(
            "city_id",
            "observed_at",
            name="measurements_unique_city_time",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger,
        primary_key=True,
    )

    city_id: Mapped[int] = mapped_column(
        ForeignKey(
            "cities.id",
            ondelete="CASCADE",
        ),
        nullable=False,
    )

    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )

    fetched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    european_aqi: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    us_aqi: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    pm2_5: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    pm10: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    nitrogen_dioxide: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    ozone: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    carbon_monoxide: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    uv_index: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    source: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        default="open-meteo",
    )

    source_status_code: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
        default=200,
    )

    city: Mapped[City] = relationship(
        back_populates="measurements",
    )