"""Small RabbitMQ helper shared by the producer and consumer."""

import json
import os

import pika


REFRESH_QUEUE = os.getenv("RABBITMQ_QUEUE", "wildlife.refresh")
FAILED_QUEUE = f"{REFRESH_QUEUE}.failed"


def connection_parameters() -> pika.ConnectionParameters:
    """Build RabbitMQ connection settings from environment variables."""

    credentials = pika.PlainCredentials(
        os.getenv("RABBITMQ_USER", "wildlife_queue"),
        os.getenv("RABBITMQ_PASSWORD", "wildlife_queue_password"),
    )
    return pika.ConnectionParameters(
        host=os.getenv("RABBITMQ_HOST", "127.0.0.1"),
        port=int(os.getenv("RABBITMQ_PORT", "5672")),
        credentials=credentials,
        heartbeat=60,
        blocked_connection_timeout=30,
        connection_attempts=1,
        socket_timeout=10,
    )


def open_connection() -> pika.BlockingConnection:
    """Open one blocking RabbitMQ connection."""

    return pika.BlockingConnection(connection_parameters())


def declare_queues(channel) -> None:
    """Create durable work and failed-message queues when absent."""

    channel.queue_declare(queue=REFRESH_QUEUE, durable=True)
    channel.queue_declare(queue=FAILED_QUEUE, durable=True)


def publish_json(
    channel,
    queue_name: str,
    payload: dict,
    headers: dict | None = None,
) -> None:
    """Publish one persistent JSON message."""

    channel.basic_publish(
        exchange="",
        routing_key=queue_name,
        body=json.dumps(payload).encode("utf-8"),
        properties=pika.BasicProperties(
            content_type="application/json",
            delivery_mode=2,
            headers=headers or {},
        ),
        mandatory=True,
    )
