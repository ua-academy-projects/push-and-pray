from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import HistoryRecord
from app.schemas import HistoryRecordCreate


def create_history_record(
    session: Session,
    payload: HistoryRecordCreate,
) -> HistoryRecord:
    """Create and persist one history record."""

    record = HistoryRecord(
        request_type=payload.request_type,
        query_parameters=payload.query_parameters,
        response_data=payload.response_data,
        result_count=payload.result_count,
        source=payload.source,
        source_status_code=payload.source_status_code,
    )

    session.add(record)
    session.commit()
    session.refresh(record)

    return record


def get_history_records(
    session: Session,
    *,
    limit: int,
    offset: int,
) -> tuple[list[HistoryRecord], int]:
    """Return paginated records and total record count."""

    total_statement = select(func.count()).select_from(HistoryRecord)
    total = session.scalar(total_statement) or 0

    records_statement = (
        select(HistoryRecord)
        .order_by(
            HistoryRecord.created_at.desc(),
            HistoryRecord.id.desc(),
        )
        .offset(offset)
        .limit(limit)
    )

    records = list(session.scalars(records_statement).all())

    return records, total


def get_history_record_by_id(
    session: Session,
    record_id: int,
) -> HistoryRecord | None:
    """Return one record by primary key."""

    return session.get(HistoryRecord, record_id)