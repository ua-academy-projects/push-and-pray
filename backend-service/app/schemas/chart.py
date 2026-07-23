from datetime import date

from pydantic import BaseModel, ConfigDict, Field


class ChartPeriod(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    from_date: date | None = Field(default=None, alias="from")
    to_date: date | None = Field(default=None, alias="to")
    available_days: int


class TemperaturePoint(BaseModel):
    date: date
    average: float
    minimum: float
    maximum: float


class HumidityPoint(BaseModel):
    date: date
    average: float | None = None


class PrecipitationPoint(BaseModel):
    date: date
    total: float


class WindPoint(BaseModel):
    date: date
    average: float | None = None
    maximum: float


class ChartDataResponse(BaseModel):
    period: ChartPeriod
    temperature: list[TemperaturePoint]
    humidity: list[HumidityPoint]
    precipitation: list[PrecipitationPoint]
    wind: list[WindPoint]
