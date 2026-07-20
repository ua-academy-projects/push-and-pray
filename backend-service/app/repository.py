from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.models import AirQualityMeasurement, City
from app.schemas import MeasurementCreate


def list_active_cities(
    db: Session,
) -> list[City]:
    statement = (
        select(City)
        .where(City.is_active.is_(True))
        .order_by(City.name)
    )

    return list(
        db.scalars(statement).all()
    )


def get_city_by_code(
    db: Session,
    city_code: str,
) -> City | None:
    statement = select(City).where(
        City.code == city_code.lower()
    )

    return db.scalar(statement)


def create_measurement(
    db: Session,
    payload: MeasurementCreate,
) -> tuple[AirQualityMeasurement, bool]:
    city = get_city_by_code(
        db,
        payload.city_code,
    )

    if city is None:
        raise ValueError(
            f"Unknown city code: {payload.city_code}"
        )

    measurement = AirQualityMeasurement(
        city_id=city.id,
        observed_at=payload.observed_at,
        european_aqi=payload.european_aqi,
        us_aqi=payload.us_aqi,
        pm2_5=payload.pm2_5,
        pm10=payload.pm10,
        nitrogen_dioxide=payload.nitrogen_dioxide,
        ozone=payload.ozone,
        carbon_monoxide=payload.carbon_monoxide,
        uv_index=payload.uv_index,
        source=payload.source,
        source_status_code=payload.source_status_code,
    )

    db.add(measurement)

    try:
        db.commit()
        db.refresh(measurement)

        measurement = db.scalar(
            select(AirQualityMeasurement)
            .options(
                joinedload(
                    AirQualityMeasurement.city
                )
            )
            .where(
                AirQualityMeasurement.id
                == measurement.id
            )
        )

        if measurement is None:
            raise RuntimeError(
                "Created measurement could not be reloaded"
            )

        return measurement, True

    except IntegrityError:
        db.rollback()

        existing = db.scalar(
            select(AirQualityMeasurement)
            .options(
                joinedload(
                    AirQualityMeasurement.city
                )
            )
            .where(
                AirQualityMeasurement.city_id
                == city.id,
                AirQualityMeasurement.observed_at
                == payload.observed_at,
            )
        )

        if existing is None:
            raise

        return existing, False


def get_latest_measurement(
    db: Session,
    city_id: int,
) -> AirQualityMeasurement | None:
    statement = (
        select(AirQualityMeasurement)
        .where(
            AirQualityMeasurement.city_id == city_id
        )
        .order_by(
            AirQualityMeasurement.observed_at.desc()
        )
        .limit(1)
    )

    return db.scalar(statement)


def get_measurement_history(
    db: Session,
    city_id: int,
    hours: int,
) -> list[AirQualityMeasurement]:
    start_time = (
        datetime.now(timezone.utc)
        - timedelta(hours=hours)
    )

    statement = (
        select(AirQualityMeasurement)
        .where(
            AirQualityMeasurement.city_id == city_id,
            AirQualityMeasurement.observed_at >= start_time,
        )
        .order_by(
            AirQualityMeasurement.observed_at.asc()
        )
    )

    return list(
        db.scalars(statement).all()
    )