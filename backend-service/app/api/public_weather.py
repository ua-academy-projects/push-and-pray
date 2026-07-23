from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.chart import ChartDataResponse
from app.schemas.persistence import DailyWeatherOut, WeatherForecastResponse, WeatherHistoryResponse
from app.schemas.statistics import DailyStatisticsResponse, PeriodStatisticsResponse
from app.schemas.sync import SyncStatusResponse
from app.schemas.weather import WeatherHourlyResponse, WeatherResponse
from app.services import chart_service, statistics_service, weather_query_service, weather_read_service

router = APIRouter(prefix="/api", tags=["public"])


def _validate_range(from_date: date | None, to_date: date | None) -> None:
    if from_date is not None and to_date is not None and from_date > to_date:
        raise HTTPException(status_code=400, detail="'from' must not be after 'to'")


@router.get("/weather", response_model=WeatherResponse)
def get_weather(db: Session = Depends(get_db)) -> WeatherResponse:
    """Reads persisted data directly from PostgreSQL. Never calls Open-Meteo, never triggers a
    synchronization -- including on the very first request against an empty database, where it
    returns a clearly-marked no-data response instead of fabricating one."""
    return weather_read_service.get_weather(db)


@router.get("/weather/daily", response_model=WeatherHistoryResponse)
def get_weather_daily(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
) -> WeatherHistoryResponse:
    """Recorded daily weather, newest first. Replaces Stage 1's `GET /api/weather/history?days=`
    -- no artificial cap; omit both `from` and `to` for every stored date ("all available
    data")."""
    _validate_range(from_date, to_date)
    return weather_query_service.get_daily(db, from_date, to_date)


@router.get("/weather/daily/{target_date}", response_model=DailyWeatherOut)
def get_weather_daily_by_date(target_date: date, db: Session = Depends(get_db)) -> DailyWeatherOut:
    """The raw recorded daily row for one date -- distinct from
    `/weather/statistics/daily/{date}`, which reframes the same date as a statistics summary
    (dominant condition, method used for the average, etc.)."""
    result = weather_query_service.get_daily_by_date(db, target_date)
    if result is None:
        raise HTTPException(status_code=404, detail="No recorded data for that date")
    return result


@router.get("/weather/forecast", response_model=WeatherForecastResponse)
def get_weather_forecast(days: int = Query(10, ge=1, le=16), db: Session = Depends(get_db)) -> WeatherForecastResponse:
    """Reads exclusively from `daily_forecast` -- never `daily_weather`, and vice versa (see
    `docs/architecture.md` §9). Predicted, not recorded -- the UI should visually distinguish
    this from `/weather/daily`."""
    return weather_query_service.get_forecast(db, days)


@router.get("/weather/hourly", response_model=WeatherHourlyResponse)
def get_weather_hourly(db: Session = Depends(get_db)) -> WeatherHourlyResponse:
    return weather_read_service.get_hourly(db)


@router.get("/weather/statistics/daily/{target_date}", response_model=DailyStatisticsResponse)
def get_statistics_for_day(target_date: date, db: Session = Depends(get_db)) -> DailyStatisticsResponse:
    result = statistics_service.get_daily_statistics(db, target_date)
    if result is None:
        raise HTTPException(status_code=404, detail="No recorded data for that date")
    return result


@router.get("/weather/statistics", response_model=PeriodStatisticsResponse)
def get_statistics_for_period(
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
    db: Session = Depends(get_db),
) -> PeriodStatisticsResponse:
    _validate_range(from_date, to_date)
    return statistics_service.get_period_statistics(db, from_date, to_date)


@router.get("/weather/statistics/all", response_model=PeriodStatisticsResponse)
def get_statistics_all_time(db: Session = Depends(get_db)) -> PeriodStatisticsResponse:
    return statistics_service.get_all_time_statistics(db)


@router.get("/weather/charts", response_model=ChartDataResponse)
def get_weather_charts(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
) -> ChartDataResponse:
    _validate_range(from_date, to_date)
    return chart_service.get_chart_data(db, from_date, to_date)


@router.get("/sync-status", response_model=SyncStatusResponse)
def get_sync_status(db: Session = Depends(get_db)) -> SyncStatusResponse:
    return weather_read_service.get_sync_status(db)
