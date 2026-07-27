"""Return success when a delivery ID has been committed by History."""

import sys

from history_service.config import get_settings
from history_service.models import BlacklistSnapshot
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-history-delivery.py DELIVERY_ID")
    engine = create_engine(get_settings().database_url(), pool_pre_ping=True)
    try:
        with Session(engine) as session:
            found = session.scalar(
                select(BlacklistSnapshot.snapshot_id).where(
                    BlacklistSnapshot.delivery_id == sys.argv[1]
                )
            )
    finally:
        engine.dispose()
    raise SystemExit(0 if found is not None else 1)


if __name__ == "__main__":
    main()
