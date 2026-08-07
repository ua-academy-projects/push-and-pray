"""Internet-facing Fetcher service and six-month refresh publisher."""

import os
import time
import uuid
from datetime import datetime, timezone

import pika
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel, Field

from fetcher_service.gbif import get_gbif_data, refresh_gbif_data
from shared.rabbitmq import (
    REFRESH_QUEUE,
    declare_queues,
    open_connection,
    publish_json,
)


load_dotenv()

SERVICE_HOST = os.getenv("SERVICE_HOST", "127.0.0.1")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", "8002"))
INTERNAL_SERVICE_TOKEN = os.getenv(
    "INTERNAL_SERVICE_TOKEN",
    "change-this-internal-service-token",
)
PUBLISH_ATTEMPTS = int(os.getenv("FETCHER_PUBLISH_ATTEMPTS", "5"))
RETRY_DELAY_SECONDS = int(
    os.getenv("FETCHER_RETRY_DELAY_SECONDS", "10")
)

app = FastAPI(title="Ukraine Wildlife Fetcher")


class TrackedSpecies(BaseModel):
    """One species already matched and stored by Backend."""

    scientific_name: str = Field(min_length=2, max_length=200)
    taxon_key: int = Field(gt=0)


class RefreshRequest(BaseModel):
    """Species that Fetcher must refresh directly from GBIF."""

    species: list[TrackedSpecies] = Field(max_length=1000)


def require_internal_token(token: str) -> None:
    """Reject calls that did not originate from another trusted service."""

    if token != INTERNAL_SERVICE_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid service token.")


def publish_refresh_job() -> dict:
    """Publish one refresh job with exponential-backoff retry."""

    payload = {
        "job_id": str(uuid.uuid4()),
        "requested_at": datetime.now(timezone.utc).isoformat(),
        "source": "systemd-timer",
    }

    for attempt in range(1, PUBLISH_ATTEMPTS + 1):
        connection = None
        try:
            connection = open_connection()
            channel = connection.channel()
            channel.confirm_delivery()
            declare_queues(channel)
            publish_json(channel, REFRESH_QUEUE, payload)
            return payload
        except (pika.exceptions.AMQPError, OSError) as error:
            if attempt == PUBLISH_ATTEMPTS:
                raise HTTPException(
                    status_code=503,
                    detail=(
                        "RabbitMQ publish failed after "
                        f"{attempt} attempts."
                    ),
                ) from error

            delay = RETRY_DELAY_SECONDS * 2 ** (attempt - 1)
            print(
                f"Publish attempt {attempt} failed: {error}. "
                f"Retrying in {delay} seconds.",
                flush=True,
            )
            time.sleep(delay)
        finally:
            if connection and connection.is_open:
                connection.close()

    raise HTTPException(status_code=503, detail="Refresh was not published.")


@app.get("/health")
def health() -> dict:
    """Report that the Fetcher HTTP process is running."""

    return {"status": "ok", "internet_client": "gbif"}


@app.get("/animals/fetch")
def fetch_animal(
    name: str = Query(min_length=2, max_length=100),
    include_samples: bool = Query(default=True),
    x_internal_service_token: str = Header(default=""),
) -> dict:
    """Validate a name, call GBIF and return data to Backend."""

    require_internal_token(x_internal_service_token)
    return get_gbif_data(name.strip(), include_samples=include_samples)


@app.post("/animals/refresh")
def refresh_species(
    payload: RefreshRequest,
    x_internal_service_token: str = Header(default=""),
) -> dict:
    """Fetch current GBIF counts for species already tracked by Backend."""

    require_internal_token(x_internal_service_token)
    items = []
    failed = []

    for species in payload.species:
        try:
            items.append(
                refresh_gbif_data(
                    species.scientific_name,
                    species.taxon_key,
                )
            )
        except HTTPException as error:
            failed.append(
                {
                    "scientific_name": species.scientific_name,
                    "status_code": error.status_code,
                }
            )

    return {"items": items, "failed": failed}


@app.post("/internal/publish-refresh")
def schedule_refresh(
    x_internal_service_token: str = Header(default=""),
) -> dict:
    """Publish the six-month job when the local systemd timer calls us."""

    require_internal_token(x_internal_service_token)
    job = publish_refresh_job()
    print(
        f"Refresh job {job['job_id']} published to {REFRESH_QUEUE}.",
        flush=True,
    )
    return {"status": "published", **job}


if __name__ == "__main__":
    uvicorn.run(app, host=SERVICE_HOST, port=SERVICE_PORT)
