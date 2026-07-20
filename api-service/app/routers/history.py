from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.clients.history import HistoryClient, HistoryClientError
from app.config import Settings, get_settings
from app.schemas import HistoryRecordDetail, HistoryRecordList


router = APIRouter(
    prefix="/api/history",
    tags=["history"],
)


def get_history_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> HistoryClient:
    return HistoryClient(settings)


HistoryDependency = Annotated[
    HistoryClient,
    Depends(get_history_client),
]


@router.get(
    "",
    response_model=HistoryRecordList,
)
async def list_history(
    history: HistoryDependency,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> HistoryRecordList:
    try:
        return await history.list_records(
            limit=limit,
            offset=offset,
        )

    except HistoryClientError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="History Service is unavailable",
        ) from exc


@router.get(
    "/{record_id}",
    response_model=HistoryRecordDetail,
)
async def get_history_record(
    record_id: int,
    history: HistoryDependency,
) -> HistoryRecordDetail:
    try:
        return await history.get_record(record_id)

    except HistoryClientError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not retrieve history record",
        ) from exc