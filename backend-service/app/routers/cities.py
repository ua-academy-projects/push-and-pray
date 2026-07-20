from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db_session
from app.repository import list_active_cities
from app.schemas import CityResponse


router = APIRouter(
    prefix="/api/cities",
    tags=["cities"],
)


DatabaseSession = Annotated[
    Session,
    Depends(get_db_session),
]


@router.get(
    "",
    response_model=list[CityResponse],
)
def get_cities(
    db: DatabaseSession,
) -> list[CityResponse]:
    return list_active_cities(db)