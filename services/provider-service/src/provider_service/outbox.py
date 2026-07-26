"""Small durable SQLite outbox for normalized blacklist deliveries."""

import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from pydantic import ValidationError

from provider_service.schemas import (
    BlacklistSnapshotDelivery,
    BlacklistSnapshotMessage,
    InternalBlacklistResponse,
)


def _serialize_time(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Outbox timestamps must include a timezone.")
    return value.astimezone(UTC).isoformat()


def _parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value).astimezone(UTC)


@dataclass(frozen=True)
class PendingMessage:
    message: BlacklistSnapshotMessage
    attempts: int
    next_attempt_at: datetime


class BlacklistOutbox:
    """Persist complete messages before any RabbitMQ publish attempt."""

    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=FULL")
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS blacklist_outbox (
                delivery_id TEXT PRIMARY KEY,
                snapshot_key TEXT NOT NULL UNIQUE,
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt_at TEXT NOT NULL,
                delivered_at TEXT
            );
            CREATE INDEX IF NOT EXISTS ix_blacklist_outbox_pending
                ON blacklist_outbox(delivered_at, next_attempt_at);
            CREATE TABLE IF NOT EXISTS worker_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS delivered_snapshot_keys (
                snapshot_key TEXT PRIMARY KEY,
                delivery_id TEXT NOT NULL UNIQUE,
                delivered_at TEXT NOT NULL
            );
            """
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def enqueue(
        self,
        *,
        delivery_id: UUID,
        snapshot: InternalBlacklistResponse,
        now: datetime,
    ) -> None:
        message = BlacklistSnapshotMessage(
            schema_version=1,
            message_type="blacklist.snapshot.complete",
            delivery_id=delivery_id,
            correlation_id=delivery_id,
            producer="aegis-provider-service",
            provider=snapshot.provider,
            created_at=now,
            snapshot=snapshot,
        )
        snapshot_key = f"{snapshot.provider}:{_serialize_time(snapshot.generated_at)}"
        timestamp = _serialize_time(now)
        with self.connection:
            delivered = self.connection.execute(
                """
                SELECT 1 FROM delivered_snapshot_keys WHERE snapshot_key = ?
                """,
                (snapshot_key,),
            ).fetchone()
            if delivered is not None:
                return
            self.connection.execute(
                """
                INSERT OR IGNORE INTO blacklist_outbox
                    (
                        delivery_id, snapshot_key, payload_json,
                        created_at, next_attempt_at
                    )
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    str(delivery_id),
                    snapshot_key,
                    message.model_dump_json(),
                    timestamp,
                    timestamp,
                ),
            )

    def next_pending(self, now: datetime) -> PendingMessage | None:
        row = self.connection.execute(
            """
            SELECT delivery_id, payload_json, created_at, attempts, next_attempt_at
            FROM blacklist_outbox
            WHERE delivered_at IS NULL AND next_attempt_at <= ?
            ORDER BY next_attempt_at, created_at, delivery_id
            LIMIT 1
            """,
            (_serialize_time(now),),
        ).fetchone()
        if row is None:
            return None
        message = self._load_message(row)
        return PendingMessage(
            message=message,
            attempts=int(row["attempts"]),
            next_attempt_at=_parse_time(row["next_attempt_at"]),
        )

    def mark_published(self, delivery_id: UUID, *, published_at: datetime) -> None:
        """Compact an outbox row only after publisher confirmation."""
        with self.connection:
            row = self.connection.execute(
                """
                SELECT snapshot_key FROM blacklist_outbox
                WHERE delivery_id = ?
                """,
                (str(delivery_id),),
            ).fetchone()
            if row is None:
                return
            self.connection.execute(
                """
                INSERT OR IGNORE INTO delivered_snapshot_keys
                    (snapshot_key, delivery_id, delivered_at)
                VALUES (?, ?, ?)
                """,
                (
                    row["snapshot_key"],
                    str(delivery_id),
                    _serialize_time(published_at),
                ),
            )
            self.connection.execute(
                "DELETE FROM blacklist_outbox WHERE delivery_id = ?",
                (str(delivery_id),),
            )

    def _load_message(self, row: sqlite3.Row) -> BlacklistSnapshotMessage:
        payload_json = str(row["payload_json"])
        try:
            return BlacklistSnapshotMessage.model_validate_json(payload_json)
        except ValidationError:
            legacy = BlacklistSnapshotDelivery.model_validate_json(payload_json)
            if str(legacy.delivery_id) != str(row["delivery_id"]):
                raise ValueError(
                    "Legacy outbox delivery ID does not match its row."
                ) from None
            message = BlacklistSnapshotMessage(
                schema_version=1,
                message_type="blacklist.snapshot.complete",
                delivery_id=legacy.delivery_id,
                correlation_id=legacy.delivery_id,
                producer="aegis-provider-service",
                provider=legacy.snapshot.provider,
                created_at=_parse_time(str(row["created_at"])),
                snapshot=legacy.snapshot,
            )
            with self.connection:
                self.connection.execute(
                    """
                    UPDATE blacklist_outbox
                    SET payload_json = ?
                    WHERE delivery_id = ?
                    """,
                    (message.model_dump_json(), str(legacy.delivery_id)),
                )
            return message

    def reschedule(
        self, delivery_id: UUID, *, attempts: int, next_attempt_at: datetime
    ) -> None:
        with self.connection:
            self.connection.execute(
                """
                UPDATE blacklist_outbox
                SET attempts = ?, next_attempt_at = ?
                WHERE delivery_id = ? AND delivered_at IS NULL
                """,
                (attempts, _serialize_time(next_attempt_at), str(delivery_id)),
            )

    def pending_count(self) -> int:
        row = self.connection.execute(
            "SELECT COUNT(*) FROM blacklist_outbox WHERE delivered_at IS NULL"
        ).fetchone()
        assert row is not None
        return int(row[0])

    def get_next_poll_at(self) -> datetime | None:
        row = self.connection.execute(
            "SELECT value FROM worker_state WHERE key = 'next_poll_at'"
        ).fetchone()
        return _parse_time(row["value"]) if row is not None else None

    def set_poll_state(self, *, next_poll_at: datetime, failure_attempts: int) -> None:
        with self.connection:
            self.connection.execute(
                """
                INSERT INTO worker_state(key, value) VALUES ('next_poll_at', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (_serialize_time(next_poll_at),),
            )
            self.connection.execute(
                """
                INSERT INTO worker_state(key, value)
                VALUES ('poll_failure_attempts', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (str(failure_attempts),),
            )

    def get_poll_failure_attempts(self) -> int:
        row = self.connection.execute(
            "SELECT value FROM worker_state WHERE key = 'poll_failure_attempts'"
        ).fetchone()
        return int(row["value"]) if row is not None else 0

    def next_due_at(self) -> datetime | None:
        row = self.connection.execute(
            """
            SELECT MIN(next_attempt_at)
            FROM blacklist_outbox
            WHERE delivered_at IS NULL
            """
        ).fetchone()
        if row is None or row[0] is None:
            return None
        return _parse_time(row[0])
