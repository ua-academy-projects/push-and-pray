from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db_session
from app.repository import (
    create_history_record,
    get_history_record_by_id,
    get_history_records,
)
from app.schemas import (
    HistoryRecordCreate,
    HistoryRecordCreated,
    HistoryRecordDetail,
    HistoryRecordList,
    HistoryRecordSummary,
)


router = APIRouter(
    prefix="/history",
    tags=["history"],
)

DatabaseSession = Annotated[Session, Depends(get_db_session)]


@router.post(
    "",
    response_model=HistoryRecordCreated,
    status_code=status.HTTP_201_CREATED,
)
def create_record(
    payload: HistoryRecordCreate,
    session: DatabaseSession,
) -> HistoryRecordCreated:
    """Save one successful external API response."""

    try:
        record = create_history_record(session, payload)
    except SQLAlchemyError as exc:
        session.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save history record",
        ) from exc

    return HistoryRecordCreated(
        id=record.id,
        created_at=record.created_at,
        message="History record created",
    )


@router.get(
    "",
    response_model=HistoryRecordList,
)
def list_records(
    session: DatabaseSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> HistoryRecordList:
    """Return history summaries ordered from newest to oldest."""

    try:
        records, total = get_history_records(
            session,
            limit=limit,
            offset=offset,
        )
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve history records",
        ) from exc

    return HistoryRecordList(
        items=[
            HistoryRecordSummary.model_validate(record)
            for record in records
        ],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get(
    "/{record_id}",
    response_model=HistoryRecordDetail,
)
def get_record(
    record_id: int,
    session: DatabaseSession,
) -> HistoryRecordDetail:
    """Return one complete history record."""

    try:
        record = get_history_record_by_id(session, record_id)
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve history record",
        ) from exc

    if record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="History record not found",
        )

    return HistoryRecordDetail.model_validate(record)