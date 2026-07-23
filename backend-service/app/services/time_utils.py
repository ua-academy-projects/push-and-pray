from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

KYIV = ZoneInfo("Europe/Kyiv")


def kyiv_today() -> date:
    """Today's calendar date as seen in Europe/Kyiv, regardless of the server's own timezone."""
    return datetime.now(KYIV).date()


def kyiv_date_to_utc_range(day: date) -> tuple[datetime, datetime]:
    """The [start, end) UTC instant range covering one Europe/Kyiv calendar day."""
    start_local = datetime.combine(day, time.min, tzinfo=KYIV)
    end_local = datetime.combine(day + timedelta(days=1), time.min, tzinfo=KYIV)
    return start_local.astimezone(ZoneInfo("UTC")), end_local.astimezone(ZoneInfo("UTC"))
