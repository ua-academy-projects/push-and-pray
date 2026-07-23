"""Buckets Open-Meteo's WMO weather codes into the four coarse categories the statistics
endpoints report counts for (rainy/snowy/clear/cloudy days) and use for "dominant condition".
Fog (45, 48) is folded into "cloudy" -- the spec asks for exactly these four buckets, not a
fifth for fog."""

CLEAR_CODES = {0, 1}
CLOUDY_CODES = {2, 3, 45, 48}
RAIN_CODES = {51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99}
SNOW_CODES = {71, 73, 75, 77, 85, 86}

BUCKET_ORDER = ("clear", "cloudy", "rain", "snow")


def bucket_for_code(weather_code: int) -> str:
    if weather_code in CLEAR_CODES:
        return "clear"
    if weather_code in RAIN_CODES:
        return "rain"
    if weather_code in SNOW_CODES:
        return "snow"
    # Cloudy is the catch-all: known cloudy/fog codes, and any WMO code this bucketing
    # doesn't otherwise recognize -- better than raising on an unexpected code from Open-Meteo.
    return "cloudy"
