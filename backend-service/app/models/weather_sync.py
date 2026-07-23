import enum
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy import Enum as SAEnum
from sqlalchemy import func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class SyncStatus(str, enum.Enum):
    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"


class TriggerType(str, enum.Enum):
    STARTUP = "startup"
    SCHEDULER = "scheduler"
    INTERNAL_ENDPOINT = "internal_endpoint"


class WeatherSync(Base):
    """Audit trail: one new row per synchronization attempt. Never updated in place, never deleted."""

    __tablename__ = "weather_syncs"

    id: Mapped[int] = mapped_column(primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("locations.id", ondelete="CASCADE"), nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[SyncStatus] = mapped_column(
        SAEnum(SyncStatus, native_enum=False, length=20, values_callable=lambda enum_cls: [e.value for e in enum_cls]),
        nullable=False,
    )
    source: Mapped[str] = mapped_column(String(50), nullable=False, default="Open-Meteo")
    trigger_type: Mapped[TriggerType] = mapped_column(
        SAEnum(
            TriggerType, native_enum=False, length=30, values_callable=lambda enum_cls: [e.value for e in enum_cls]
        ),
        nullable=False,
    )

    # Metadata about the actual outbound call to Open-Meteo (the only external API this
    # system calls) -- not just whether the sync succeeded, but what was requested, what
    # came back, and how long it took. Nullable because a `skipped` sync never calls
    # Open-Meteo at all, and a timeout means no status code was ever received.
    # Text, not a bounded VARCHAR: the real Open-Meteo request URL (with its many
    # comma-separated field lists in `current`/`hourly`/`daily`) runs to 700+ characters --
    # discovered via end-to-end testing against the real API, not anticipated up front.
    open_meteo_request_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    open_meteo_status_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    open_meteo_duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    records_received: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_records_received: Mapped[int | None] = mapped_column(Integer, nullable=True)
    forecast_records_received: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hourly_records_received: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
