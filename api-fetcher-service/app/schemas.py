from datetime import datetime

from pydantic import BaseModel, ConfigDict


class City(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    code: str
    name: str
    country: str
    latitude: float
    longitude: float
    timezone: str | None = None
    is_active: bool


class AirQualityMeasurementCreate(BaseModel):
    city_code: str
    observed_at: datetime

    european_aqi: float | None = None
    us_aqi: float | None = None
    pm2_5: float | None = None
    pm10: float | None = None
    nitrogen_dioxide: float | None = None
    ozone: float | None = None
    carbon_monoxide: float | None = None
    uv_index: float | None = None

    source: str = "open-meteo"
    source_status_code: int = 200


class CityFetchResult(BaseModel):
    city_code: str
    city_name: str
    status: str
    message_id: str | None = None
    observed_at: datetime | None = None
    error: str | None = None


class FetchRunResult(BaseModel):
    started_at: datetime
    finished_at: datetime
    total_cities: int
    successful: int
    failed: int
    published: int
    results: list[CityFetchResult]


class FetchStatus(BaseModel):
    running: bool
    last_started_at: datetime | None = None
    last_finished_at: datetime | None = None
    last_result: FetchRunResult | None = None
