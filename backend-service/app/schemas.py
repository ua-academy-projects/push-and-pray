from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CityResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str
    country: str
    latitude: float
    longitude: float
    timezone: str | None
    is_active: bool


class MeasurementCreate(BaseModel):
    city_code: str = Field(
        min_length=1,
        max_length=50,
    )

    observed_at: datetime

    european_aqi: float | None = Field(
        default=None,
        ge=0,
    )

    us_aqi: float | None = Field(
        default=None,
        ge=0,
    )

    pm2_5: float | None = Field(
        default=None,
        ge=0,
    )

    pm10: float | None = Field(
        default=None,
        ge=0,
    )

    nitrogen_dioxide: float | None = Field(
        default=None,
        ge=0,
    )

    ozone: float | None = Field(
        default=None,
        ge=0,
    )

    carbon_monoxide: float | None = Field(
        default=None,
        ge=0,
    )

    uv_index: float | None = Field(
        default=None,
        ge=0,
    )

    source: str = Field(
        default="open-meteo",
        min_length=1,
        max_length=50,
    )

    source_status_code: int = Field(
        default=200,
        ge=100,
        le=599,
    )


class MeasurementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    observed_at: datetime
    fetched_at: datetime

    european_aqi: float | None
    us_aqi: float | None

    pm2_5: float | None
    pm10: float | None

    nitrogen_dioxide: float | None
    ozone: float | None
    carbon_monoxide: float | None
    uv_index: float | None

    source: str
    source_status_code: int


class MeasurementWithCityResponse(MeasurementResponse):
    city: CityResponse


class MeasurementCreateResult(BaseModel):
    created: bool
    measurement: MeasurementWithCityResponse


class DashboardResponse(BaseModel):
    city: CityResponse
    hours: int
    latest: MeasurementResponse | None
    history: list[MeasurementResponse]