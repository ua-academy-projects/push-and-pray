
import os
import time
import logging

import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend-poller")

# URL Proxy/Weather Fetcher, який поллер викликає за розкладом.
PROXY_SERVICE_URL = os.getenv("PROXY_SERVICE_URL", "http://localhost:5001")

# Список міст, які треба автоматично оновлювати - через кому в env-змінній.
WATCHED_CITIES = [
    c.strip()
    for c in os.getenv("WATCHED_CITIES", "Kyiv,Warsaw,Berlin").split(",")
    if c.strip()
]

# Інтервал між циклами опитування, секунди (900 = 15 хвилин).
POLL_INTERVAL_SECONDS = int(os.getenv("POLL_INTERVAL_SECONDS", "900"))

# До першого опитування міст Poller чекає, поки Proxy почне відповідати на
# health-check. Це важливо у Vagrant, де VM стартують паралельно.
PROXY_READY_RETRY_SECONDS = int(os.getenv("PROXY_READY_RETRY_SECONDS", "5"))
PROXY_HEALTH_TIMEOUT_SECONDS = int(os.getenv("PROXY_HEALTH_TIMEOUT_SECONDS", "3"))


def wait_for_proxy() -> None:
    """Не запускати погодні запити, доки Proxy не стане готовим."""
    health_url = f"{PROXY_SERVICE_URL.rstrip('/')}/health"
    attempt = 0

    while True:
        attempt += 1
        try:
            response = requests.get(health_url, timeout=PROXY_HEALTH_TIMEOUT_SECONDS)
            response.raise_for_status()
            logger.info("Proxy готовий до роботи: %s", health_url)
            return
        except requests.RequestException as exc:
            logger.warning(
                "Proxy ще не готовий (спроба %s): %s. Наступна перевірка через %s сек.",
                attempt,
                exc,
                PROXY_READY_RETRY_SECONDS,
            )
            time.sleep(PROXY_READY_RETRY_SECONDS)


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
    wait_for_proxy()
    while True:
        poll_once()
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
