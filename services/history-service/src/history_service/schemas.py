"""Pydantic contracts for the internal History API."""

from datetime import UTC, datetime, timedelta
from ipaddress import ip_address
from typing import Literal, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    StrictStr,
    field_validator,
    model_validator,
)

from history_service.models import (
    BlacklistSnapshot,
    BlacklistSnapshotEntry,
    IpCheckHistory,
)

MAX_COUNT = 2_147_483_647


def normalize_ip(value: str) -> str:
    """Return the canonical representation of a valid IP address."""
    try:
        return str(ip_address(value))
    except ValueError as error:
        raise ValueError("The value must be a valid IPv4 or IPv6 address.") from error


def normalize_public_ip(value: str) -> str:
    """Return the canonical representation of a globally routable IP address."""
    normalized = normalize_ip(value)
    parsed = ip_address(normalized)
    if (
        parsed.is_loopback
        or parsed.is_private
        or parsed.is_multicast
        or parsed.is_link_local
        or parsed.is_unspecified
        or not parsed.is_global
    ):
        raise ValueError("The IP address must be public.")
    return normalized


def normalize_utc(value: datetime) -> datetime:
    """Convert an aware timestamp to UTC."""
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Timestamps must include a timezone.")
    return value.astimezone(UTC)


class ApplicationCheckRequest(BaseModel):
    """Application-facing request for one reputation lookup."""

    model_config = ConfigDict(extra="forbid")

    ip_address: str = Field(min_length=1, max_length=100)
    max_age_days: int = Field(default=30, ge=1, le=365)


class ProviderReputationRequest(BaseModel):
    """Strict normalized request sent to Provider."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    max_age_days: StrictInt = Field(ge=1, le=365)

    @field_validator("ip_address")
    @classmethod
    def require_canonical_public_ip(cls, value: str) -> str:
        normalized = normalize_public_ip(value)
        if normalized != value:
            raise ValueError("The IP address must use its canonical representation.")
        return normalized


class ProviderReputationResponse(BaseModel):
    """Provider-independent response returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    is_public: StrictBool
    is_whitelisted: StrictBool | None = None
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    usage_type: StrictStr | None = Field(default=None, max_length=100)
    isp: StrictStr | None = Field(default=None, max_length=255)
    domain: StrictStr | None = Field(default=None, max_length=255)
    total_reports: StrictInt = Field(ge=0, le=MAX_COUNT)
    num_distinct_users: StrictInt = Field(ge=0, le=MAX_COUNT)
    last_reported_at: datetime | None = None
    max_age_days: StrictInt = Field(ge=1, le=365)
    source: StrictStr = Field(min_length=1, max_length=32)
    checked_at: datetime

    @field_validator("ip_address")
    @classmethod
    def validate_ip_address(cls, value: str) -> str:
        return normalize_ip(value)

    @field_validator("country_code")
    @classmethod
    def normalize_country_code(cls, value: str | None) -> str | None:
        return value.upper() if value is not None else None

    @field_validator("last_reported_at", "checked_at")
    @classmethod
    def validate_timestamps(cls, value: datetime | None) -> datetime | None:
        return normalize_utc(value) if value is not None else None

    @model_validator(mode="after")
    def validate_address_metadata(self) -> Self:
        parsed_address = ip_address(self.ip_address)
        if self.ip_version != parsed_address.version:
            raise ValueError("ip_version does not match ip_address.")
        if (
            not self.is_public
            or parsed_address.is_loopback
            or parsed_address.is_private
            or parsed_address.is_multicast
            or parsed_address.is_link_local
            or parsed_address.is_unspecified
            or not parsed_address.is_global
        ):
            raise ValueError("ip_address must be public and is_public must be true.")
        return self


class ProviderBlacklistRequest(BaseModel):
    """Strict query parameters sent to Provider's blacklist endpoint."""

    model_config = ConfigDict(extra="forbid")

    confidence_minimum: StrictInt = Field(default=90, ge=0, le=100)
    limit: StrictInt = Field(default=1000, ge=1, le=1000)


class ProviderBlacklistRequestEcho(BaseModel):
    """Strict request metadata returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    confidence_minimum: StrictInt = Field(ge=0, le=100)
    limit: StrictInt = Field(ge=1, le=1000)


class ProviderRateLimitMetadata(BaseModel):
    """Normalized rate-limit metadata returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    limit: StrictInt | None = Field(default=None, ge=0)
    remaining: StrictInt | None = Field(default=None, ge=0)
    reset_at: datetime | None = None
    retry_after_seconds: StrictInt | None = Field(default=None, ge=0)

    @field_validator("reset_at")
    @classmethod
    def validate_reset_at(cls, value: datetime | None) -> datetime | None:
        return normalize_utc(value) if value is not None else None

    @model_validator(mode="after")
    def validate_remaining(self) -> Self:
        if (
            self.limit is not None
            and self.remaining is not None
            and self.remaining > self.limit
        ):
            raise ValueError("Rate-limit remaining cannot exceed its limit.")
        return self


class ProviderBlacklistEntry(BaseModel):
    """One normalized entry returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    last_reported_at: datetime | None = None

    @field_validator("ip_address")
    @classmethod
    def require_canonical_public_ip(cls, value: str) -> str:
        normalized = normalize_public_ip(value)
        if normalized != value:
            raise ValueError("The IP address must use its canonical representation.")
        return value

    @field_validator("country_code")
    @classmethod
    def require_uppercase_country_code(cls, value: str | None) -> str | None:
        if value is not None and value != value.upper():
            raise ValueError("country_code must use uppercase characters.")
        return value

    @field_validator("last_reported_at")
    @classmethod
    def validate_last_reported_at(cls, value: datetime | None) -> datetime | None:
        return normalize_utc(value) if value is not None else None

    @model_validator(mode="after")
    def validate_address_metadata(self) -> Self:
        if self.ip_version != ip_address(self.ip_address).version:
            raise ValueError("ip_version does not match ip_address.")
        return self


class ProviderBlacklistResponse(BaseModel):
    """Complete normalized blacklist snapshot returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    provider: Literal["AbuseIPDB"]
    generated_at: datetime
    fetched_at: datetime
    request: ProviderBlacklistRequestEcho
    rate_limit: ProviderRateLimitMetadata
    items: list[ProviderBlacklistEntry] = Field(max_length=1000)

    @field_validator("generated_at", "fetched_at")
    @classmethod
    def validate_timestamps(cls, value: datetime) -> datetime:
        return normalize_utc(value)

    @model_validator(mode="after")
    def validate_complete_snapshot(self) -> Self:
        if len(self.items) > self.request.limit:
            raise ValueError("Blacklist item count exceeds the requested limit.")
        return self


class BlacklistSnapshotMessage(BaseModel):
    """Versioned complete-snapshot message consumed from RabbitMQ."""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1]
    message_type: Literal["blacklist.snapshot.complete"]
    delivery_id: UUID
    correlation_id: UUID
    producer: Literal["aegis-provider-service"]
    provider: Literal["AbuseIPDB"]
    created_at: datetime
    snapshot: ProviderBlacklistResponse

    @field_validator("created_at")
    @classmethod
    def validate_created_at(cls, value: datetime) -> datetime:
        return normalize_utc(value)

    @model_validator(mode="after")
    def validate_provider_matches_snapshot(self) -> Self:
        if self.provider != self.snapshot.provider:
            raise ValueError("Message provider does not match snapshot provider.")
        return self


class BlacklistSnapshotDelivery(BaseModel):
    """Authenticated Provider delivery of one normalized snapshot."""

    model_config = ConfigDict(extra="forbid")

    delivery_id: UUID
    snapshot: ProviderBlacklistResponse


class CheckCreate(ProviderReputationResponse):
    """A normalized successful lookup ready for persistence."""

    request_id: UUID


class HistoryRecord(CheckCreate):
    """Serialized History record returned to callers."""

    history_id: StrictInt = Field(gt=0)

    @classmethod
    def from_record(cls, record: IpCheckHistory) -> Self:
        """Convert an ORM record without exposing it through the API."""

        def as_utc(value: datetime | None) -> datetime | None:
            return value.replace(tzinfo=UTC) if value is not None else None

        checked_at = as_utc(record.checked_at)
        if checked_at is None:
            raise ValueError("Persisted checked_at cannot be null.")
        return cls(
            history_id=record.id,
            request_id=UUID(record.request_id),
            ip_address=record.ip_address,
            ip_version=record.ip_version,
            is_public=record.is_public,
            is_whitelisted=record.is_whitelisted,
            abuse_confidence_score=record.abuse_confidence_score,
            country_code=record.country_code,
            usage_type=record.usage_type,
            isp=record.isp,
            domain=record.domain,
            total_reports=record.total_reports,
            num_distinct_users=record.num_distinct_users,
            last_reported_at=as_utc(record.last_reported_at),
            max_age_days=record.max_age_days,
            source=record.source,
            checked_at=checked_at,
        )


class HistoryList(BaseModel):
    """One page of History records."""

    items: list[HistoryRecord]
    model_config = ConfigDict(extra="forbid")

    limit: StrictInt = Field(ge=1, le=100)
    offset: StrictInt = Field(ge=0, le=MAX_COUNT)
    total: StrictInt = Field(ge=0, le=MAX_COUNT)


class HistoryListQuery(BaseModel):
    """Validated list query parameters."""

    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)
    ip_address: str | None = None

    @field_validator("ip_address")
    @classmethod
    def normalize_filter_ip(cls, value: str | None) -> str | None:
        return normalize_ip(value) if value is not None else None


class ErrorDetail(BaseModel):
    """Stable error details."""

    model_config = ConfigDict(extra="forbid")

    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)
    request_id: StrictStr = Field(min_length=1, max_length=36)


class ProviderRetryMetadata(BaseModel):
    """Validated retry metadata returned with a Provider error."""

    model_config = ConfigDict(extra="forbid")

    retry_after_seconds: StrictInt | None = Field(default=None, ge=0)
    reset_at: datetime | None = None

    @field_validator("reset_at")
    @classmethod
    def validate_reset_at(cls, value: datetime | None) -> datetime | None:
        return normalize_utc(value) if value is not None else None


class ProviderErrorDetail(BaseModel):
    """Strict error details returned across the Provider boundary."""

    model_config = ConfigDict(extra="forbid")

    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)
    request_id: StrictStr = Field(min_length=1, max_length=36)
    retry: ProviderRetryMetadata | None = None


class ErrorResponse(BaseModel):
    """Stable API error envelope."""

    error: ErrorDetail


class ProviderErrorResponse(BaseModel):
    """Strict error envelope returned by Provider."""

    model_config = ConfigDict(extra="forbid")

    error: ProviderErrorDetail


class BlacklistEntryPageQuery(BaseModel):
    """Validated pagination for one snapshot's entries."""

    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=100, ge=1, le=100)
    offset: int = Field(default=0, ge=0)


class BlacklistEntryQuery(BlacklistEntryPageQuery):
    """Validated filters and pagination for latest snapshot entries."""

    ip_version: Literal[4, 6] | None = None
    minimum_score: int | None = Field(default=None, ge=0, le=100)
    country_code: str | None = Field(
        default=None, min_length=2, max_length=2, pattern=r"^[A-Z]{2}$"
    )


class BlacklistSnapshotListQuery(BaseModel):
    """Validated pagination for stored snapshots."""

    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)


class BlacklistSnapshotSummary(BaseModel):
    """Application-facing snapshot metadata."""

    model_config = ConfigDict(extra="forbid")

    snapshot_id: StrictInt = Field(gt=0)
    provider: StrictStr = Field(min_length=1, max_length=32)
    provider_generated_at: datetime
    fetched_at: datetime
    confidence_minimum: StrictInt = Field(ge=0, le=100)
    requested_limit: StrictInt = Field(ge=1, le=1000)
    returned_count: StrictInt = Field(ge=0, le=1000)

    @classmethod
    def from_record(cls, record: BlacklistSnapshot) -> Self:
        return cls(
            snapshot_id=record.snapshot_id,
            provider=record.provider,
            provider_generated_at=record.provider_generated_at.replace(tzinfo=UTC),
            fetched_at=record.fetched_at.replace(tzinfo=UTC),
            confidence_minimum=record.confidence_minimum,
            requested_limit=record.requested_limit,
            returned_count=record.returned_count,
        )


class BlacklistEntryResponse(BaseModel):
    """Application-facing normalized blacklist entry."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    last_reported_at: datetime | None = None

    @classmethod
    def from_record(cls, record: BlacklistSnapshotEntry) -> Self:
        return cls(
            ip_address=record.ip_address,
            ip_version=record.ip_version,
            abuse_confidence_score=record.abuse_confidence_score,
            country_code=record.country_code,
            last_reported_at=(
                record.last_reported_at.replace(tzinfo=UTC)
                if record.last_reported_at is not None
                else None
            ),
        )


class BlacklistPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snapshot: BlacklistSnapshotSummary
    items: list[BlacklistEntryResponse]
    limit: StrictInt = Field(ge=1, le=100)
    offset: StrictInt = Field(ge=0)
    total: StrictInt = Field(ge=0)


class BlacklistSnapshotList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[BlacklistSnapshotSummary]
    limit: StrictInt = Field(ge=1, le=100)
    offset: StrictInt = Field(ge=0)
    total: StrictInt = Field(ge=0)


class BlacklistLastError(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)


class BlacklistStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    polling_owner: Literal["provider"] = "provider"
    state: Literal["empty", "ready", "syncing", "stale", "degraded"]
    sync_in_progress: StrictBool
    latest_snapshot_id: StrictInt | None = Field(default=None, gt=0)
    latest_provider_generated_at: datetime | None = None
    latest_fetched_at: datetime | None = None
    last_attempt_at: datetime | None = None
    last_success_at: datetime | None = None
    next_attempt_at: datetime | None = None
    rate_limit_limit: StrictInt | None = Field(default=None, ge=0)
    rate_limit_remaining: StrictInt | None = Field(default=None, ge=0)
    rate_limit_reset_at: datetime | None = None
    data_stale: StrictBool
    last_error: BlacklistLastError | None = None


class BlacklistAnalyticsQuery(BaseModel):
    """Bounded query for accepted-snapshot churn analytics."""

    model_config = ConfigDict(extra="forbid")

    pair_limit: int = Field(default=10, ge=1, le=30)


class BlacklistTurnoverQuery(BaseModel):
    """Bounded UTC range for persisted turnover summaries."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    from_: datetime = Field(alias="from")
    to: datetime
    interval: Literal["hour", "day", "week"]

    @field_validator("from_", "to")
    @classmethod
    def validate_range_timestamp(cls, value: datetime) -> datetime:
        return normalize_utc(value)

    @model_validator(mode="after")
    def validate_range(self) -> Self:
        if self.to <= self.from_:
            raise ValueError("'to' must be later than 'from'.")
        first = self._period_start(self.from_)
        last = self._period_start(self.to - timedelta(microseconds=1))
        seconds = {"hour": 3600, "day": 86400, "week": 604800}[self.interval]
        point_count = int((last - first).total_seconds() // seconds) + 1
        if point_count > 366:
            raise ValueError("Turnover range exceeds the 366-point limit.")
        return self

    def _period_start(self, value: datetime) -> datetime:
        day_start = value.replace(hour=0, minute=0, second=0, microsecond=0)
        if self.interval == "hour":
            return value.replace(minute=0, second=0, microsecond=0)
        if self.interval == "day":
            return day_start
        return day_start - timedelta(days=day_start.weekday())


class BlacklistTurnoverPoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period_start: datetime
    turnover_percent: float | None
    added_count: StrictInt | None = Field(default=None, ge=0, le=1000)
    removed_count: StrictInt | None = Field(default=None, ge=0, le=1000)
    snapshot_id: StrictInt | None = Field(default=None, gt=0)

    @field_validator("period_start")
    @classmethod
    def validate_period_start(cls, value: datetime) -> datetime:
        return normalize_utc(value)


class BlacklistTurnoverResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    from_: datetime = Field(alias="from")
    to: datetime
    interval: Literal["hour", "day", "week"]
    points: list[BlacklistTurnoverPoint] = Field(max_length=366)


class BlacklistAnalyticsSnapshot(BaseModel):
    """Latest accepted snapshot represented in the analytics response."""

    model_config = ConfigDict(extra="forbid")

    snapshot_id: StrictInt = Field(gt=0)
    provider_generated_at: datetime
    confidence_minimum: StrictInt = Field(ge=0, le=100)
    requested_limit: StrictInt = Field(ge=1, le=1000)
    returned_count: StrictInt = Field(ge=0, le=1000)
    result_limit_reached: StrictBool


class BlacklistScoreBucket(BaseModel):
    model_config = ConfigDict(extra="forbid")

    minimum: StrictInt = Field(ge=0, le=100)
    maximum: StrictInt = Field(ge=0, le=100)
    count: StrictInt = Field(ge=0, le=1000)

    @model_validator(mode="after")
    def validate_range(self) -> Self:
        if self.maximum < self.minimum:
            raise ValueError("Score bucket maximum cannot be below its minimum.")
        return self


class BlacklistCountryCount(BaseModel):
    model_config = ConfigDict(extra="forbid")

    country_code: StrictStr = Field(min_length=2, max_length=2, pattern=r"^[A-Z]{2}$")
    count: StrictInt = Field(ge=0, le=1000)


class BlacklistCountryDistribution(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[BlacklistCountryCount] = Field(max_length=10)
    unknown_count: StrictInt = Field(ge=0, le=1000)
    other_count: StrictInt = Field(ge=0, le=1000)


class BlacklistIpVersionCount(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ip_version: Literal[4, 6]
    count: StrictInt = Field(ge=0, le=1000)


class BlacklistSnapshotChurn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    current_snapshot_id: StrictInt = Field(gt=0)
    previous_snapshot_id: StrictInt = Field(gt=0)
    added: StrictInt = Field(ge=0, le=1000)
    removed: StrictInt = Field(ge=0, le=1000)
    retained: StrictInt = Field(ge=0, le=1000)


class BlacklistAnalyticsResponse(BaseModel):
    """Database-derived analytics over bounded accepted blacklist snapshots."""

    model_config = ConfigDict(extra="forbid")

    latest_snapshot: BlacklistAnalyticsSnapshot | None
    score_distribution: list[BlacklistScoreBucket] = Field(max_length=12)
    top_countries: BlacklistCountryDistribution
    ip_versions: list[BlacklistIpVersionCount] = Field(max_length=2)
    snapshot_churn: list[BlacklistSnapshotChurn] = Field(max_length=30)

    @model_validator(mode="after")
    def validate_latest_totals(self) -> Self:
        if self.latest_snapshot is None:
            if (
                self.score_distribution
                or self.top_countries.items
                or self.top_countries.unknown_count
                or self.top_countries.other_count
                or self.ip_versions
                or self.snapshot_churn
            ):
                raise ValueError("Empty analytics cannot contain snapshot data.")
            return self

        expected = self.latest_snapshot.returned_count
        if sum(item.count for item in self.score_distribution) != expected:
            raise ValueError("Score distribution must match the latest snapshot.")
        if (
            sum(item.count for item in self.top_countries.items)
            + self.top_countries.unknown_count
            + self.top_countries.other_count
            != expected
        ):
            raise ValueError("Country distribution must match the latest snapshot.")
        if sum(item.count for item in self.ip_versions) != expected:
            raise ValueError("IP version distribution must match the latest snapshot.")
        return self
