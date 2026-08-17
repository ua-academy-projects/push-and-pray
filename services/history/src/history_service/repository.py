from __future__ import annotations

from datetime import datetime

from sqlalchemy import Select, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from .models import PriceObservation
from .schemas import ObservationCreate


def insert_observations(session: Session, observations: list[ObservationCreate]) -> tuple[int, int]:
    """Insert observations idempotently without committing.

    Callers that need atomicity with other writes (e.g. marking an event as
    processed) commit the enclosing transaction themselves.
    """
    values = [item.model_dump(mode="python") for item in observations]
    statement = (
        insert(PriceObservation)
        .values(values)
        .on_conflict_do_nothing(index_elements=["instrument_code", "scheduled_for"])
        .returning(PriceObservation.id)
    )
    inserted = len(session.execute(statement).scalars().all())
    return inserted, len(observations) - inserted


def insert_batch(session: Session, observations: list[ObservationCreate]) -> tuple[int, int]:
    inserted, duplicates = insert_observations(session, observations)
    session.commit()
    return inserted, duplicates


def _filtered_query(
    instrument: str | None,
    category: str | None,
    date_from: datetime | None,
    date_to: datetime | None,
) -> Select[tuple[PriceObservation]]:
    query = select(PriceObservation)
    if instrument:
        query = query.where(PriceObservation.instrument_code == instrument)
    if category:
        query = query.where(PriceObservation.category == category)
    if date_from:
        query = query.where(PriceObservation.source_observed_at >= date_from)
    if date_to:
        query = query.where(PriceObservation.source_observed_at <= date_to)
    return query


def list_observations(
    session: Session,
    instrument: str | None,
    category: str | None,
    date_from: datetime | None,
    date_to: datetime | None,
    limit: int,
    offset: int,
) -> list[PriceObservation]:
    query = _filtered_query(instrument, category, date_from, date_to)
    query = query.order_by(PriceObservation.source_observed_at.desc()).limit(limit).offset(offset)
    return list(session.execute(query).scalars())


def latest_observations(session: Session) -> list[PriceObservation]:
    ranked = select(
        PriceObservation.id,
        func.row_number()
        .over(
            partition_by=PriceObservation.instrument_code,
            order_by=PriceObservation.source_observed_at.desc(),
        )
        .label("row_number"),
    ).subquery()
    query = (
        select(PriceObservation)
        .join(ranked, ranked.c.id == PriceObservation.id)
        .where(ranked.c.row_number == 1)
        .order_by(PriceObservation.instrument_code)
    )
    return list(session.execute(query).scalars())


def list_instruments(session: Session) -> list[dict[str, str]]:
    query = (
        select(
            PriceObservation.instrument_code,
            PriceObservation.instrument_name,
            PriceObservation.category,
            PriceObservation.currency,
            PriceObservation.unit,
        )
        .distinct()
        .order_by(PriceObservation.instrument_code)
    )
    return [
        {"code": row[0], "name": row[1], "category": row[2], "currency": row[3], "unit": row[4]}
        for row in session.execute(query)
    ]
