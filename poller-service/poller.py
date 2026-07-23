
import os
import time
import logging

import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend-poller")

# URL, за яким поллер звертається до самого Backend (як звичайний клієнт).
PROXY_SERVICE_URL = os.getenv("PROXY_SERVICE_URL", "http://localhost:5001")

# Список міст, які треба автоматично оновлювати - через кому в env-змінній.
WATCHED_CITIES = [
    c.strip()
    for c in os.getenv("WATCHED_CITIES", "Kyiv,Warsaw,Berlin").split(",")
    if c.strip()
]

# Інтервал між циклами опитування, секунди (900 = 15 хвилин).
POLL_INTERVAL_SECONDS = int(os.getenv("POLL_INTERVAL_SECONDS", "900"))


def poll_once() -> None:
    """Один прохід: оновити дані для кожного міста зі списку спостереження."""
    for city in WATCHED_CITIES:
        try:
            resp = requests.get(
                f"{PROXY_SERVICE_URL}/api/current",
                params={"city": city},
                timeout=15,
            )
            resp.raise_for_status()
            logger.info("Автооновлення виконано для міста %s", city)
        except requests.RequestException:
            logger.exception("Не вдалося автооновити дані для міста %s", city)


def main() -> None:
    logger.info(
        "Poller стартував. Міста: %s. Інтервал: %s сек.",
        WATCHED_CITIES,
        POLL_INTERVAL_SECONDS,
    )
    while True:
        poll_once()
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
