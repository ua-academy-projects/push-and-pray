"""UI-owned models for History Service's application contract."""

from datetime import datetime
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

MAX_COUNT = 2_147_483_647


class CheckResult(BaseModel):
    """Normalized check rendered by the UI."""

    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    history_id: StrictInt = Field(gt=0)
    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    is_public: StrictBool
    is_whitelisted: StrictBool | None
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    usage_type: StrictStr | None = Field(default=None, max_length=100)
    isp: StrictStr | None = Field(default=None, max_length=255)
    domain: StrictStr | None = Field(default=None, max_length=255)
    total_reports: StrictInt = Field(ge=0, le=MAX_COUNT)
    num_distinct_users: StrictInt = Field(ge=0, le=MAX_COUNT)
    last_reported_at: datetime | None
    max_age_days: StrictInt = Field(ge=1, le=365)
    source: StrictStr = Field(min_length=1, max_length=32)
    checked_at: datetime

    @field_validator("ip_address")
    @classmethod
    def validate_ip_address(cls, value: str) -> str:
        try:
            parsed = ip_address(value)
        except ValueError as error:
            raise ValueError("The value must be a valid IP address.") from error
        if (
            parsed.is_loopback
            or parsed.is_private
            or parsed.is_multicast
            or parsed.is_link_local
            or parsed.is_unspecified
            or not parsed.is_global
        ):
            raise ValueError("The IP address must be public.")
        return str(parsed)

    @field_validator("last_reported_at", "checked_at")
    @classmethod
    def validate_timestamps(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("Timestamps must include a timezone.")
        return value

    @model_validator(mode="after")
    def validate_address_metadata(self) -> Self:
        if self.ip_version != ip_address(self.ip_address).version or not self.is_public:
            raise ValueError("IP address metadata is inconsistent.")
        return self


class HistoryPage(BaseModel):
    """Recent persisted checks returned by History Service."""

    model_config = ConfigDict(extra="forbid")

    items: list[CheckResult]
    limit: StrictInt = Field(ge=1, le=100)
    offset: StrictInt = Field(ge=0, le=MAX_COUNT)
    total: StrictInt = Field(ge=0, le=MAX_COUNT)


class BlacklistLastError(BaseModel):
    """Safe summary of the latest blacklist synchronization failure."""

    model_config = ConfigDict(extra="forbid")

    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)


class BlacklistStatus(BaseModel):
    """Blacklist synchronization state exposed by History Service."""

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

    @field_validator(
        "latest_provider_generated_at",
        "latest_fetched_at",
        "last_attempt_at",
        "last_success_at",
        "next_attempt_at",
        "rate_limit_reset_at",
    )
    @classmethod
    def validate_status_timestamps(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("Timestamps must include a timezone.")
        return value


class BlacklistPollStatus(BaseModel):
    """Minimal same-origin status used by blacklist page polling."""

    model_config = ConfigDict(extra="forbid")

    state: Literal["empty", "ready", "syncing", "stale", "degraded"]
    latest_snapshot_id: StrictInt | None = Field(default=None, gt=0)
    data_stale: StrictBool


class BlacklistSnapshotSummary(BaseModel):
    """Metadata for the latest complete blacklist snapshot."""

    model_config = ConfigDict(extra="forbid")

    snapshot_id: StrictInt = Field(gt=0)
    provider: StrictStr = Field(min_length=1, max_length=32)
    provider_generated_at: datetime
    fetched_at: datetime
    confidence_minimum: StrictInt = Field(ge=0, le=100)
    requested_limit: StrictInt = Field(ge=1, le=1000)
    returned_count: StrictInt = Field(ge=0, le=1000)

    @field_validator("provider_generated_at", "fetched_at")
    @classmethod
    def validate_snapshot_timestamps(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamps must include a timezone.")
        return value


class BlacklistEntry(BaseModel):
    """One normalized blacklist entry rendered by the UI."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    last_reported_at: datetime | None = None

    @field_validator("ip_address")
    @classmethod
    def validate_blacklist_ip(cls, value: str) -> str:
        try:
            parsed = ip_address(value)
        except ValueError as error:
            raise ValueError("The value must be a valid IP address.") from error
        if str(parsed) != value:
            raise ValueError("The IP address must use canonical representation.")
        return value

    @field_validator("last_reported_at")
    @classmethod
    def validate_last_reported_at(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("Timestamps must include a timezone.")
        return value

    @model_validator(mode="after")
    def validate_blacklist_ip_version(self) -> Self:
        if ip_address(self.ip_address).version != self.ip_version:
            raise ValueError("IP address metadata is inconsistent.")
        return self


class BlacklistPage(BaseModel):
    """Paginated entries from History Service's latest successful snapshot."""

    model_config = ConfigDict(extra="forbid")

    snapshot: BlacklistSnapshotSummary
    items: list[BlacklistEntry]
    limit: StrictInt = Field(ge=1, le=100)
    offset: StrictInt = Field(ge=0, le=MAX_COUNT)
    total: StrictInt = Field(ge=0, le=MAX_COUNT)


class BlacklistAnalyticsSnapshot(BaseModel):
    """Latest accepted snapshot represented by History analytics."""

    model_config = ConfigDict(extra="forbid")

    snapshot_id: StrictInt = Field(gt=0)
    provider_generated_at: datetime
    confidence_minimum: StrictInt = Field(ge=0, le=100)
    requested_limit: StrictInt = Field(ge=1, le=1000)
    returned_count: StrictInt = Field(ge=0, le=1000)
    result_limit_reached: StrictBool

    @field_validator("provider_generated_at")
    @classmethod
    def validate_generated_at(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamps must include a timezone.")
        return value


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


class BlacklistAnalytics(BaseModel):
    """Strict UI boundary for database-derived blacklist analytics."""

    model_config = ConfigDict(extra="forbid")

    latest_snapshot: BlacklistAnalyticsSnapshot | None
    score_distribution: list[BlacklistScoreBucket] = Field(max_length=12)
    top_countries: BlacklistCountryDistribution
    ip_versions: list[BlacklistIpVersionCount] = Field(max_length=2)
    snapshot_churn: list[BlacklistSnapshotChurn] = Field(max_length=30)

    @model_validator(mode="after")
    def validate_totals_and_ordering(self) -> Self:
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
            raise ValueError("Score distribution does not match the snapshot.")
        if (
            sum(item.count for item in self.top_countries.items)
            + self.top_countries.unknown_count
            + self.top_countries.other_count
            != expected
        ):
            raise ValueError("Country distribution does not match the snapshot.")
        if sum(item.count for item in self.ip_versions) != expected:
            raise ValueError("IP version distribution does not match the snapshot.")
        if [item.ip_version for item in self.ip_versions] != [4, 6]:
            raise ValueError("IP version analytics must be ordered as IPv4 and IPv6.")
        return self


class BlacklistTurnoverPoint(BaseModel):
    """One persisted History turnover bucket."""

    model_config = ConfigDict(extra="forbid")

    period_start: datetime
    turnover_percent: float | None
    added_count: StrictInt | None = Field(default=None, ge=0, le=1000)
    removed_count: StrictInt | None = Field(default=None, ge=0, le=1000)
    snapshot_id: StrictInt | None = Field(default=None, gt=0)

    @field_validator("period_start")
    @classmethod
    def validate_period_start(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamps must include a timezone.")
        return value


class BlacklistTurnover(BaseModel):
    """Strict UI boundary for History turnover time-series data."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    from_: datetime | None = Field(alias="from")
    to: datetime | None
    interval: Literal["hour", "day", "week", "month"]
    requested_period: Literal["custom", "all"] = "custom"
    effective_start: datetime | None = None
    effective_end: datetime | None = None
    granularity: Literal["hour", "day", "week", "month"] = "day"
    bucket_count: StrictInt = Field(default=0, ge=0, le=366)
    points: list[BlacklistTurnoverPoint] = Field(max_length=366)

    @field_validator("from_", "to", "effective_start", "effective_end")
    @classmethod
    def validate_range_timestamp(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamps must include a timezone.")
        return value

    @model_validator(mode="after")
    def validate_metadata(self) -> Self:
        if "granularity" not in self.model_fields_set:
            self.granularity = self.interval
        if "bucket_count" not in self.model_fields_set:
            self.bucket_count = len(self.points)
        if self.granularity != self.interval:
            raise ValueError("Granularity must match the response interval.")
        if self.bucket_count != len(self.points):
            raise ValueError("Bucket count must match the number of points.")
        return self


class ReadinessResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ready"]


class ApplicationErrorDetail(BaseModel):
    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)
    request_id: StrictStr = Field(min_length=1, max_length=36)


class ApplicationErrorResponse(BaseModel):
    error: ApplicationErrorDetail
