import asyncio

from history_service.config import Settings
from history_service.rabbitmq_messaging import RabbitMQConsumer


class InvalidMessage:
    body = b"not-json"
    redelivered = False

    def __init__(self) -> None:
        self.rejected = False

    async def reject(self, *, requeue: bool) -> None:
        assert requeue is False
        self.rejected = True


def test_invalid_rabbitmq_message_is_dead_lettered() -> None:
    async def exercise() -> None:
        consumer = RabbitMQConsumer(Settings(messaging_backend="rabbitmq"))
        message = InvalidMessage()

        await consumer._handle_message(message)  # type: ignore[arg-type]

        assert message.rejected is True

    asyncio.run(exercise())
