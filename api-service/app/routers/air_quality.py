import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.clients.history import HistoryClient, HistoryClientError
from app.clients.open_meteo import OpenMeteoClient
from app.config import Settings, get_settings
from app.exceptions import (
    ExternalServiceResponseError,
    ExternalServiceTimeoutError,
    LocationNotFoundError,
)
from app.schemas import (
    AirQualityResponse,
    HistoryCreatePayload,
)


logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/air-quality",
    tags=["air quality"],
)


def get_open_meteo_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> OpenMeteoClient:
    return OpenMeteoClient(settings)


def get_history_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> HistoryClient:
    return HistoryClient(settings)


OpenMeteoDependency = Annotated[
    OpenMeteoClient,
    Depends(get_open_meteo_client),
]

HistoryDependency = Annotated[
    HistoryClient,
    Depends(get_history_client),
]


@router.get(
    "",
    response_model=AirQualityResponse,
)
async def get_air_quality(
    city: Annotated[
        str,
        Query(
            min_length=2,
            max_length=100,
            description="City name to search for",
            examples=["Cherkasy"],
        ),
    ],
    open_meteo: OpenMeteoDependency,
    history: HistoryDependency,
) -> AirQualityResponse:
    """Retrieve and persist current air-quality data."""

    normalized_city = city.strip()

    if len(normalized_city) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="City must contain at least two non-space characters",
        )

    try:
        location = await open_meteo.geocode_city(normalized_city)

        air_quality = await open_meteo.get_current_air_quality(
            location
        )

    except LocationNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc

    except ExternalServiceTimeoutError as exc:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="Open-Meteo request timed out",
        ) from exc

    except ExternalServiceResponseError as exc:
        logger.exception("Open-Meteo request failed")

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to retrieve data from Open-Meteo",
        ) from exc

    response_without_history = {
        "location": location.model_dump(mode="json"),
        "air_quality": air_quality.model_dump(mode="json"),
        "source": "open-meteo",
    }

    history_payload = HistoryCreatePayload(
        request_type="air_quality",
        query_parameters={
            "city": normalized_city,
            "latitude": location.latitude,
            "longitude": location.longitude,
        },
        response_data=response_without_history,
        result_count=1,
        source="open-meteo",
        source_status_code=200,
    )

    history_saved = True

    try:
        await history.save_record(history_payload)
    except HistoryClientError:
        history_saved = False
        logger.exception(
            "Fresh air-quality data was retrieved, "
            "but history persistence failed"
        )

    return AirQualityResponse(
        location=location,
        air_quality=air_quality,
        source="open-meteo",
        history_saved=history_saved,
    )