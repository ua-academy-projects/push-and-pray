"""Internet-isolated Backend+History service for the wildlife application."""

import os
import threading
from contextlib import asynccontextmanager

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from api_service.fetcher_client import (
    fetcher_is_ready,
    get_animal_data,
    refresh_species,
)
from api_service.queue_consumer import (
    consume_refresh_jobs,
    rabbitmq_is_ready,
)
from api_service.repository import (
    create_tables,
    database_is_ready,
    get_changes,
    get_tracked_species,
    save_observation,
)


load_dotenv()

SERVICE_HOST = os.getenv("SERVICE_HOST", "127.0.0.1")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", "8000"))
DATA_MEANING = (
    "Це кількість записів про спостереження у GBIF, "
    "а не точна чисельність живих тварин."
)


class CompareRequest(BaseModel):
    """Names selected by the user for one comparison chart."""

    names: list[str] = Field(min_length=2, max_length=8)


create_tables()


def store_result(data: dict) -> dict:
    """Store a GBIF result and return the change-detection status."""

    return save_observation(
        data["scientific_name"],
        data["taxon_key"],
        data["observation_count"],
    )


def refresh_all_tracked_species() -> dict:
    """Ask Fetcher to refresh every PostgreSQL baseline."""

    refreshed = []
    tracked_species = get_tracked_species()
    fetcher_result = refresh_species(tracked_species)

    for data in fetcher_result["items"]:
        tracking = store_result(data)
        refreshed.append(
            {
                "scientific_name": data["scientific_name"],
                "status": tracking["status"],
            }
        )

    return {
        "status": (
            "completed"
            if not fetcher_result["failed"]
            else "partially_failed"
        ),
        "refreshed": refreshed,
        "failed": fetcher_result["failed"],
    }


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Start the RabbitMQ consumer together with the HTTP application."""

    consumer = threading.Thread(
        target=consume_refresh_jobs,
        args=(refresh_all_tracked_species,),
        name="rabbitmq-refresh-consumer",
        daemon=True,
    )
    consumer.start()
    yield


app = FastAPI(
    title="Ukraine Wildlife Backend and History",
    lifespan=lifespan,
)


@app.get("/health")
def health() -> dict:
    """Report PostgreSQL, RabbitMQ and Fetcher dependencies."""

    if not database_is_ready():
        raise HTTPException(
            status_code=503,
            detail="PostgreSQL is unavailable.",
        )
    if not rabbitmq_is_ready():
        raise HTTPException(
            status_code=503,
            detail="RabbitMQ is unavailable.",
        )
    if not fetcher_is_ready():
        raise HTTPException(
            status_code=503,
            detail="Fetcher is unavailable.",
        )
    return {
        "status": "ok",
        "database": "ok",
        "rabbitmq": "ok",
        "fetcher": "ok",
    }


@app.get("/animals/search")
def search_animal(
    name: str = Query(min_length=2, max_length=100),
) -> dict:
    """Ask Fetcher for GBIF data after an explicit user search."""

    data = get_animal_data(name.strip())
    data["tracking"] = store_result(data)
    data["changes"] = get_changes()
    data["meaning"] = DATA_MEANING
    return data


@app.post("/animals/compare")
def compare_animals(payload: CompareRequest) -> dict:
    """Compare GBIF occurrence counts for two to eight selected species."""

    names = []
    for raw_name in payload.names:
        cleaned_name = raw_name.strip()
        if cleaned_name and cleaned_name.casefold() not in {
            item.casefold() for item in names
        }:
            names.append(cleaned_name)

    if len(names) < 2:
        raise HTTPException(
            status_code=422,
            detail="Введіть щонайменше два різні види.",
        )

    gbif_results = []
    for name in names:
        data = get_animal_data(name, include_samples=False)
        gbif_results.append(data)

    items = []
    for data in gbif_results:
        store_result(data)
        items.append(
            {
                "query": data["query"],
                "scientific_name": data["scientific_name"],
                "taxon_key": data["taxon_key"],
                "observation_count": data["observation_count"],
                "source_url": data["source_url"],
                "image_url": data.get("image_url"),
                "image_source_url": data.get("image_source_url"),
                "image_creator": data.get("image_creator"),
                "image_license": data.get("image_license"),
            }
        )

    return {"items": items, "meaning": DATA_MEANING}


@app.get("/animals/changes")
def animal_changes(
    limit: int = Query(default=10, ge=1, le=50),
) -> list[dict]:
    """Return the real GBIF count changes stored by Backend."""

    return get_changes(limit)


if __name__ == "__main__":
    uvicorn.run(app, host=SERVICE_HOST, port=SERVICE_PORT)
