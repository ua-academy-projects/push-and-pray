from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    Identity,
    Integer,
    SmallInteger,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class HistoryRecord(Base):
    """SQLAlchemy mapping for the history_records PostgreSQL table."""

    __tablename__ = "history_records"

    __table_args__ = (
        CheckConstraint(
            "length(trim(request_type)) > 0",
            name="history_records_request_type_not_blank",
        ),
        CheckConstraint(
            "length(trim(source)) > 0",
            name="history_records_source_not_blank",
        ),
        CheckConstraint(
            "result_count >= 0",
            name="history_records_result_count_non_negative",
        ),
        CheckConstraint(
            "source_status_code BETWEEN 100 AND 599",
            name="history_records_source_status_code_valid",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger,
        Identity(always=True),
        primary_key=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    )

    request_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )

    query_parameters: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )

    response_data: Mapped[dict[str, Any] | list[Any]] = mapped_column(
        JSONB,
        nullable=False,
    )

    result_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    source: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )

    source_status_code: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )