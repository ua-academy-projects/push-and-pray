import uuid

from redis import Redis

from app.schemas.session import UIState, UIStatePatch

_KEY_PREFIX = "session:"


def _key(session_id: str) -> str:
    return f"{_KEY_PREFIX}{session_id}"


def load_or_create(redis: Redis, session_id: str | None, ttl_seconds: int) -> tuple[str, UIState]:
    """Looks up an existing session by id and refreshes its TTL; mints a new one (default
    state) if no id was given, or the given id has expired/never existed. Never raises on an
    unknown id -- an expired session is indistinguishable from a first visit."""
    if session_id:
        raw = redis.get(_key(session_id))
        if raw is not None:
            redis.expire(_key(session_id), ttl_seconds)
            return session_id, UIState.model_validate_json(raw)

    new_id = str(uuid.uuid4())
    state = UIState()
    redis.set(_key(new_id), state.model_dump_json(), ex=ttl_seconds)
    return new_id, state


def patch_state(redis: Redis, session_id: str, patch: UIStatePatch, ttl_seconds: int) -> UIState:
    """Merges only the fields the caller actually sent into the stored state under the same id
    (recreating a default-plus-patch entry if the session had expired), and refreshes the TTL."""
    raw = redis.get(_key(session_id))
    current = UIState.model_validate_json(raw) if raw is not None else UIState()
    # model_copy(update=...) would assign the patch's raw nested dicts (e.g. a partial
    # averages_range) without coercing them back into DateRangeState -- re-validate the merged
    # dict instead so a partial nested patch still comes out as a well-formed UIState.
    merged = {**current.model_dump(), **patch.model_dump(exclude_unset=True)}
    updated = UIState.model_validate(merged)
    redis.set(_key(session_id), updated.model_dump_json(), ex=ttl_seconds)
    return updated
