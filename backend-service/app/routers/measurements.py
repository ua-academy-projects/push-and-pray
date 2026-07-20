from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    status,
)
from sqlalchemy.orm import Session

from app.database import get_db_session
from app.repository import (
    create_measurement,
    get_city_by_code,
    get_latest_measurement,
    get_measurement_history,
)
from app.schemas import (
    DashboardResponse,
    MeasurementCreate,
    MeasurementCreateResult,
)


router = APIRouter(
    prefix="/api",
    tags=["air quality"],
)


DatabaseSession = Annotated[
    Session,
    Depends(get_db_session),
]


@router.post(
    "/measurements",
    response_model=MeasurementCreateResult,
    status_code=status.HTTP_201_CREATED,
)
def save_measurement(
    payload: MeasurementCreate,
    db: DatabaseSession,
) -> MeasurementCreateResult:
    try:
        measurement, created = create_measurement(
            db,
            payload,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc

    return MeasurementCreateResult(
        created=created,
        measurement=measurement,
    )


@router.get(
    "/dashboard",
    response_model=DashboardResponse,
)
def get_dashboard(
    db: DatabaseSession,
    city: Annotated[
        str,
        Query(
            min_length=1,
            max_length=50,
            examples=["kyiv"],
        ),
    ],
    hours: Annotated[
        int,
        Query(
            ge=1,
            le=168,
        ),
    ] = 24,
) -> DashboardResponse:
    city_record = get_city_by_code(
        db,
        city,
    )

    if city_record is None or not city_record.is_active:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"City '{city}' was not found",
        )

    latest = get_latest_measurement(
        db,
        city_record.id,
    )

    history = get_measurement_history(
        db,
        city_record.id,
        hours,
    )

    return DashboardResponse(
        city=city_record,
        hours=hours,
        latest=latest,
        history=history,
    )