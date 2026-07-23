from datetime import datetime

from pydantic import BaseModel, ConfigDict


class LocationIn(BaseModel):
    name: str
    country: str
    latitude: float
    longitude: float
    timezone: str


class LocationOut(LocationIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime
