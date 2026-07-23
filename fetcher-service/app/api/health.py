from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict:
    """Service status only -- the Fetcher has no database to check connectivity against.
    Never calls Open-Meteo, never has side effects."""
    return {"status": "ok"}
