"""HTTP client used by the isolated Backend to reach Fetcher."""

import os

import requests
from fastapi import HTTPException


FETCHER_URL = os.getenv(
    "FETCHER_SERVICE_URL",
    "http://127.0.0.1:8002",
).rstrip("/")
INTERNAL_SERVICE_TOKEN = os.getenv(
    "INTERNAL_SERVICE_TOKEN",
    "change-this-internal-service-token",
)
FETCHER_HEADERS = {
    "X-Internal-Service-Token": INTERNAL_SERVICE_TOKEN,
}


def _request(
    method: str,
    path: str,
    *,
    timeout: int,
    **kwargs,
) -> dict:
    """Call Fetcher and preserve validation errors for the UI."""

    try:
        response = requests.request(
            method,
            f"{FETCHER_URL}{path}",
            headers=FETCHER_HEADERS,
            timeout=timeout,
            **kwargs,
        )
        if response.status_code in {404, 422}:
            raise HTTPException(
                status_code=response.status_code,
                detail=response.json().get(
                    "detail",
                    "Fetcher не знайшов цей вид.",
                ),
            )
        response.raise_for_status()
        return response.json()
    except HTTPException:
        raise
    except requests.Timeout as error:
        raise HTTPException(
            status_code=504,
            detail="Fetcher відповідає надто довго.",
        ) from error
    except (requests.RequestException, ValueError) as error:
        raise HTTPException(
            status_code=502,
            detail="Fetcher зараз недоступний.",
        ) from error


def get_animal_data(
    name: str,
    include_samples: bool = True,
) -> dict:
    """Ask Fetcher to validate a name and obtain GBIF data."""

    return _request(
        "GET",
        "/animals/fetch",
        params={
            "name": name,
            "include_samples": str(include_samples).lower(),
        },
        timeout=45,
    )


def refresh_species(species: list[dict]) -> dict:
    """Ask Fetcher to update already tracked species from GBIF."""

    return _request(
        "POST",
        "/animals/refresh",
        json={"species": species},
        timeout=max(60, len(species) * 25),
    )


def fetcher_is_ready() -> bool:
    """Return whether Backend can reach the Fetcher HTTP process."""

    try:
        response = requests.get(f"{FETCHER_URL}/health", timeout=5)
        return response.ok
    except requests.RequestException:
        return False
