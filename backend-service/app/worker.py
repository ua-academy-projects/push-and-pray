import asyncio
import logging

from app.broker.consumer import consume_forever
from app.config import get_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main() -> None:
    asyncio.run(consume_forever(get_settings()))


if __name__ == "__main__":
    main()
