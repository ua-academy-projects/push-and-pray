import logging
import time

import psycopg2

from settings import DB_HOST, DB_NAME, DB_PASSWORD, DB_PORT, DB_USER

logger = logging.getLogger(__name__)


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=10,
        application_name="weather-backend",
    )


def wait_for_database(max_attempts=60, delay=5):
    for attempt in range(1, max_attempts + 1):
        try:
            connection = get_connection()
            connection.close()
            logger.info("PostgreSQL is available")
            return
        except psycopg2.Error as error:
            logger.warning(
                "PostgreSQL unavailable (%s/%s): %s",
                attempt,
                max_attempts,
                error,
            )
            time.sleep(delay)

    raise RuntimeError("Could not connect to PostgreSQL")
