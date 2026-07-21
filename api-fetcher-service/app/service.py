import asyncio
import logging
from datetime import datetime, timezone

from app.clients.backend import BackendClient
from app.clients.open_meteo import OpenMeteoClient
from app.exceptions import (
    BackendServiceError,
    ExternalServiceError,
)
from app.schemas import (
    City,
    CityFetchResult,
    FetchRunResult,
    FetchStatus,
)


logger = logging.getLogger(__name__)


class FetchService:
    """Coordinates scheduled air-quality collection."""

    def __init__(
        self,
        backend_client: BackendClient,
        open_meteo_client: OpenMeteoClient,
    ) -> None:
        self._backend = backend_client
        self._open_meteo = open_meteo_client

        self._lock = asyncio.Lock()
        self._status = FetchStatus(running=False)

    @property
    def status(self) -> FetchStatus:
        return self._status.model_copy(deep=True)

    async def run_fetch(self) -> FetchRunResult:
        if self._lock.locked():
            raise RuntimeError(
                "An air-quality fetch is already running"
            )

        async with self._lock:
            started_at = datetime.now(timezone.utc)

            self._status.running = True
            self._status.last_started_at = started_at

            logger.info(
                "Starting scheduled air-quality fetch"
            )

            try:
                cities = await self._backend.list_cities()

                active_cities = [
                    city
                    for city in cities
                    if city.is_active
                ]

                results = await self._fetch_all_cities(
                    active_cities
                )

                finished_at = datetime.now(timezone.utc)

                successful = sum(
                    result.status == "success"
                    for result in results
                )

                failed = sum(
                    result.status == "failed"
                    for result in results
                )

                created = sum(
                    result.created is True
                    for result in results
                )

                duplicates = sum(
                    result.created is False
                    for result in results
                )

                run_result = FetchRunResult(
                    started_at=started_at,
                    finished_at=finished_at,
                    total_cities=len(active_cities),
                    successful=successful,
                    failed=failed,
                    created=created,
                    duplicates=duplicates,
                    results=results,
                )

                self._status.last_finished_at = finished_at
                self._status.last_result = run_result

                logger.info(
                    "Air-quality fetch finished: "
                    "%s successful, %s failed, "
                    "%s created, %s duplicates",
                    successful,
                    failed,
                    created,
                    duplicates,
                )

                return run_result

            finally:
                self._status.running = False

    async def _fetch_all_cities(
        self,
        cities: list[City],
    ) -> list[CityFetchResult]:
        tasks = [
            self._fetch_city(city)
            for city in cities
        ]

        if not tasks:
            return []

        return list(
            await asyncio.gather(*tasks)
        )

    async def _fetch_city(
        self,
        city: City,
    ) -> CityFetchResult:
        try:
            measurement = (
                await self._open_meteo
                .fetch_current_measurement(city)
            )

            saved = await self._backend.save_measurement(
                measurement
            )

            return CityFetchResult(
                city_code=city.code,
                city_name=city.name,
                status="success",
                created=saved.created,
                measurement_id=saved.measurement.id,
                observed_at=saved.measurement.observed_at,
            )

        except (
            ExternalServiceError,
            BackendServiceError,
            ValueError,
        ) as exc:
            logger.exception(
                "Failed to fetch air quality for %s",
                city.code,
            )

            return CityFetchResult(
                city_code=city.code,
                city_name=city.name,
                status="failed",
                error=str(exc),
            )