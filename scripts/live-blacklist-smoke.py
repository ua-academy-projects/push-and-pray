"""Perform exactly one opt-in AbuseIPDB blacklist delivery for Vagrant smoke tests."""

import asyncio
import json
from datetime import UTC, datetime
from uuid import uuid4

from provider_service.blacklist_worker import create_abuseipdb_http_client
from provider_service.config import get_settings
from provider_service.outbox import BlacklistOutbox
from provider_service.provider import AbuseIPDBProvider
from provider_service.rabbitmq_publisher import AioPikaBlacklistPublisher
from provider_service.schemas import BlacklistSnapshotMessage, InternalBlacklistRequest
from provider_service.service import ReputationProxyService


async def run() -> None:
    settings = get_settings()
    api_key = settings.abuseipdb_api_key.get_secret_value()
    if not api_key or "replace" in api_key.lower() or "example" in api_key.lower():
        raise RuntimeError("A real AbuseIPDB API key is required for live mode.")

    delivery_id = uuid4()
    now = datetime.now(UTC)
    outbox = BlacklistOutbox(settings.blacklist_outbox_path)
    client = create_abuseipdb_http_client(settings)
    publisher = AioPikaBlacklistPublisher(settings)
    try:
        provider = AbuseIPDBProvider(
            client,
            operation_timeout_seconds=settings.abuseipdb_operation_timeout_seconds,
        )
        snapshot = await ReputationProxyService(clock=lambda: now).blacklist(
            InternalBlacklistRequest(
                confidence_minimum=settings.blacklist_confidence_minimum,
                limit=1000,
            ),
            provider,
        )
        outbox.enqueue(delivery_id=delivery_id, snapshot=snapshot, now=now)
        row = outbox.connection.execute(
            "SELECT payload_json FROM blacklist_outbox WHERE delivery_id = ?",
            (str(delivery_id),),
        ).fetchone()
        if row is None:
            raise RuntimeError("The live delivery was not written to the outbox.")

        message = BlacklistSnapshotMessage.model_validate_json(row["payload_json"])
        await publisher.connect()
        await publisher.publish(message)
        outbox.mark_published(delivery_id, published_at=datetime.now(UTC))
        print(
            json.dumps(
                {
                    "delivery_id": str(delivery_id),
                    "entry_count": len(snapshot.items),
                    "rate_limit_remaining": snapshot.rate_limit.remaining,
                },
                separators=(",", ":"),
            )
        )
    finally:
        await publisher.close()
        await client.aclose()
        outbox.close()


if __name__ == "__main__":
    asyncio.run(run())
