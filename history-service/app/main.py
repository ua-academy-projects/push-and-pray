import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api import health, syncs, weather
from app.exceptions import PersistenceError

logging.basicConfig(level=logging.INFO)

# NOTE: every /internal/* endpoint below is unauthenticated in this assignment (v1). In
# production this must sit behind a private network boundary and/or a shared secret between
# the Backend and History Service -- see docs/architecture.md §11.
app = FastAPI(title="SkyIvano History Service")

app.include_router(health.router)
app.include_router(weather.router)
app.include_router(syncs.router)


@app.exception_handler(PersistenceError)
def handle_persistence_error(_: Request, exc: PersistenceError) -> JSONResponse:
    # The real cause is already logged (with rollback) where it happened -- callers only
    # get a generic message, never a raw stack trace.
    return JSONResponse(status_code=500, content={"detail": str(exc)})
