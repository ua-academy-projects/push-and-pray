from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class Location(BaseModel):
    name: str
    country: str | None = None
    admin1: str | None = None

    latitude: float
    longitude: float

    timezone: str | None = None


class AirQualityData(BaseModel):
    observed_at: datetime | str

    european_aqi: float | None = None
    us_aqi: float | None = None

    pm2_5: float | None = None
    pm10: float | None = None

    nitrogen_dioxide: float | None = None
    ozone: float | None = None
    carbon_monoxide: float | None = None
    uv_index: float | None = None


class AirQualityResponse(BaseModel):
    location: Location
    air_quality: AirQualityData

    source: str = "open-meteo"
    history_saved: bool


class HistoryCreatePayload(BaseModel):
    request_type: str
    query_parameters: dict[str, Any]
    response_data: dict[str, Any] | list[Any]

    result_count: int = Field(ge=0)

    source: str
    source_status_code: int = Field(ge=100, le=599)


class HistoryRecordCreated(BaseModel):
    id: int
    created_at: datetime
    message: str


class HistoryRecordSummary(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: int
    created_at: datetime
    request_type: str
    query_parameters: dict[str, Any]
    result_count: int
    source: str
    source_status_code: int


class HistoryRecordList(BaseModel):
    items: list[HistoryRecordSummary]
    total: int
    limit: int
    offset: int


class HistoryRecordDetail(HistoryRecordSummary):
    response_data: dict[str, Any] | list[Any]