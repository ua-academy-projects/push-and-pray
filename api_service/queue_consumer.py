"""RabbitMQ consumer that asks Backend to refresh tracked species."""

import json
import os
import time

import pika

from shared.rabbitmq import (
    FAILED_QUEUE,
    REFRESH_QUEUE,
    declare_queues,
    open_connection,
    publish_json,
)


PROCESS_ATTEMPTS = int(os.getenv("BACKEND_PROCESS_ATTEMPTS", "3"))
RETRY_DELAY_SECONDS = int(
    os.getenv("BACKEND_RETRY_DELAY_SECONDS", "30")
)
RECONNECT_DELAY_SECONDS = int(
    os.getenv("RABBITMQ_RECONNECT_DELAY_SECONDS", "10")
)


def rabbitmq_is_ready() -> bool:
    """Return True when Backend can connect and declare its queues."""

    connection = None
    try:
        connection = open_connection()
        declare_queues(connection.channel())
        return True
    except (pika.exceptions.AMQPError, OSError):
        return False
    finally:
        if connection and connection.is_open:
            connection.close()


def consume_refresh_jobs(refresh_handler) -> None:
    """Consume forever, reconnecting after RabbitMQ downtime."""

    while True:
        connection = None
        try:
            connection = open_connection()
            channel = connection.channel()
            channel.confirm_delivery()
            declare_queues(channel)
            channel.basic_qos(prefetch_count=1)

            def process_message(
                current_channel,
                delivery,
                properties,
                body,
            ) -> None:
                headers = dict(properties.headers or {})
                previous_retries = int(headers.get("retry_count", 0))

                try:
                    payload = json.loads(body.decode("utf-8"))
                    result = refresh_handler()
                    if result["failed"]:
                        raise RuntimeError(
                            f"{len(result['failed'])} species failed"
                        )

                    print(
                        f"Refresh job {payload.get('job_id')} completed:",
                        f"{len(result['refreshed'])} species refreshed.",
                        flush=True,
                    )
                    current_channel.basic_ack(delivery_tag=delivery.delivery_tag)
                except Exception as error:
                    next_retry = previous_retries + 1
                    destination = (
                        REFRESH_QUEUE
                        if next_retry < PROCESS_ATTEMPTS
                        else FAILED_QUEUE
                    )
                    retry_headers = {
                        **headers,
                        "retry_count": next_retry,
                        "last_error": str(error)[:500],
                    }

                    try:
                        if destination == REFRESH_QUEUE:
                            delay = (
                                RETRY_DELAY_SECONDS
                                * 2 ** previous_retries
                            )
                            print(
                                f"Refresh attempt failed: {error}. "
                                f"Retrying in {delay} seconds.",
                                flush=True,
                            )
                            time.sleep(delay)
                        else:
                            print(
                                "Refresh attempts exhausted; "
                                f"moving message to {FAILED_QUEUE}: {error}",
                                flush=True,
                            )

                        publish_json(
                            current_channel,
                            destination,
                            json.loads(body.decode("utf-8")),
                            retry_headers,
                        )
                        current_channel.basic_ack(
                            delivery_tag=delivery.delivery_tag
                        )
                    except Exception:
                        current_channel.basic_nack(
                            delivery_tag=delivery.delivery_tag,
                            requeue=True,
                        )
                        raise

            channel.basic_consume(
                queue=REFRESH_QUEUE,
                on_message_callback=process_message,
            )
            print(
                f"Backend is waiting for messages in {REFRESH_QUEUE}.",
                flush=True,
            )
            channel.start_consuming()
        except (pika.exceptions.AMQPError, OSError) as error:
            print(
                f"RabbitMQ unavailable: {error}. "
                f"Reconnecting in {RECONNECT_DELAY_SECONDS} seconds.",
                flush=True,
            )
            time.sleep(RECONNECT_DELAY_SECONDS)
        finally:
            if connection and connection.is_open:
                connection.close()
