from fastapi import APIRouter, Query

from app.schemas.sync import SyncStatusResponse
from app.schemas.weather import WeatherHistoryResponse, WeatherHourlyResponse, WeatherResponse
from app.services import weather_read_service

router = APIRouter(prefix="/api", tags=["public"])


@router.get("/weather", response_model=WeatherResponse)
async def get_weather() -> WeatherResponse:
    """Only ever reads persisted data through the History Service. Never calls Open-Meteo,
    never triggers a synchronization -- including on the very first request against an empty
    database, where it returns a clearly-marked no-data response instead of fabricating one."""
    return await weather_read_service.get_weather()


@router.get("/weather/history", response_model=WeatherHistoryResponse)
async def get_weather_history(days: int = Query(10, ge=1, le=30)) -> WeatherHistoryResponse:
    return await weather_read_service.get_history(days)


@router.get("/weather/hourly", response_model=WeatherHourlyResponse)
async def get_weather_hourly() -> WeatherHourlyResponse:
    return await weather_read_service.get_hourly()


@router.get("/sync-status", response_model=SyncStatusResponse)
async def get_sync_status() -> SyncStatusResponse:
    return await weather_read_service.get_sync_status()
