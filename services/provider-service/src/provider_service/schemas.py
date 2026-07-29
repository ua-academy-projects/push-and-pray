"""Pydantic contracts for the internal Provider proxy."""

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


def normalize_public_ip(value: str) -> str:
    """Return a canonical public IP address or reject the value."""
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


def require_aware(value: datetime | None) -> datetime | None:
    if value is not None and (value.tzinfo is None or value.utcoffset() is None):
        raise ValueError("Timestamps must include a timezone.")
    return value


class InternalReputationRequest(BaseModel):
    """Strict normalized lookup request accepted from History."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    max_age_days: StrictInt = Field(ge=1, le=365)

    @field_validator("ip_address")
    @classmethod
    def require_normalized_public_ip(cls, value: str) -> str:
        normalized = normalize_public_ip(value)
        if value != normalized:
            raise ValueError("The IP address must use its canonical representation.")
        return normalized


class ReputationResult(BaseModel):
    """Normalized provider result before persistence."""

    model_config = ConfigDict(extra="forbid")

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
    source: StrictStr = Field(min_length=1, max_length=32)

    @field_validator("ip_address")
    @classmethod
    def validate_ip_address(cls, value: str) -> str:
        return normalize_public_ip(value)

    @field_validator("last_reported_at")
    @classmethod
    def validate_last_reported_at(cls, value: datetime | None) -> datetime | None:
        return require_aware(value)

    @model_validator(mode="after")
    def validate_address_metadata(self) -> Self:
        if self.ip_version != ip_address(self.ip_address).version or not self.is_public:
            raise ValueError("IP address metadata is inconsistent.")
        return self


class InternalReputationResponse(ReputationResult):
    """Provider-independent result returned to History."""

    max_age_days: StrictInt = Field(ge=1, le=365)
    checked_at: datetime

    @field_validator("checked_at")
    @classmethod
    def validate_checked_at(cls, value: datetime) -> datetime:
        validated = require_aware(value)
        assert validated is not None
        return validated


class InternalBlacklistRequest(BaseModel):
    """Validated query parameters for one complete blacklist request."""

    model_config = ConfigDict(extra="forbid")

    confidence_minimum: int = Field(default=90, ge=0, le=100)
    limit: int = Field(default=1000, ge=1, le=1000)


class BlacklistRequestParameters(BaseModel):
    """Parameters sent to the provider for a blacklist snapshot."""

    model_config = ConfigDict(extra="forbid")

    confidence_minimum: StrictInt = Field(ge=0, le=100)
    limit: StrictInt = Field(ge=1, le=1000)


class RateLimitMetadata(BaseModel):
    """Normalized AbuseIPDB rate-limit response headers."""

    model_config = ConfigDict(extra="forbid")

    limit: StrictInt | None = Field(default=None, ge=0)
    remaining: StrictInt | None = Field(default=None, ge=0)
    reset_at: datetime | None = None
    retry_after_seconds: StrictInt | None = Field(default=None, ge=0)

    @field_validator("reset_at")
    @classmethod
    def validate_reset_at(cls, value: datetime | None) -> datetime | None:
        return require_aware(value)

    @model_validator(mode="after")
    def validate_remaining(self) -> Self:
        if (
            self.limit is not None
            and self.remaining is not None
            and self.remaining > self.limit
        ):
            raise ValueError("Rate-limit remaining cannot exceed its limit.")
        return self


class BlacklistEntry(BaseModel):
    """One normalized entry in a complete provider blacklist snapshot."""

    model_config = ConfigDict(extra="forbid")

    ip_address: StrictStr = Field(min_length=1, max_length=39)
    ip_version: Literal[4, 6]
    abuse_confidence_score: StrictInt = Field(ge=0, le=100)
    country_code: StrictStr | None = Field(default=None, min_length=2, max_length=2)
    last_reported_at: datetime | None = None

    @field_validator("ip_address")
    @classmethod
    def validate_ip_address(cls, value: str) -> str:
        return normalize_public_ip(value)

    @field_validator("country_code")
    @classmethod
    def normalize_country_code(cls, value: str | None) -> str | None:
        return value.upper() if value is not None else None

    @field_validator("last_reported_at")
    @classmethod
    def validate_last_reported_at(cls, value: datetime | None) -> datetime | None:
        return require_aware(value)

    @model_validator(mode="after")
    def validate_address_metadata(self) -> Self:
        if self.ip_version != ip_address(self.ip_address).version:
            raise ValueError("ip_version does not match ip_address.")
        return self


class BlacklistProviderResult(BaseModel):
    """Validated provider snapshot before service response metadata is added."""

    model_config = ConfigDict(extra="forbid")

    generated_at: datetime
    rate_limit: RateLimitMetadata
    items: list[BlacklistEntry] = Field(max_length=1000)

    @field_validator("generated_at")
    @classmethod
    def validate_generated_at(cls, value: datetime) -> datetime:
        validated = require_aware(value)
        assert validated is not None
        return validated


class InternalBlacklistResponse(BlacklistProviderResult):
    """Complete normalized blacklist snapshot."""

    provider: Literal["AbuseIPDB"]
    fetched_at: datetime
    request: BlacklistRequestParameters

    @field_validator("fetched_at")
    @classmethod
    def validate_fetched_at(cls, value: datetime) -> datetime:
        validated = require_aware(value)
        assert validated is not None
        return validated


class BlacklistSnapshotMessage(BaseModel):
    """Versioned complete-snapshot message published to RabbitMQ."""

    model_config = ConfigDict(extra="forbid", revalidate_instances="always")

    schema_version: Literal[1]
    message_type: Literal["blacklist.snapshot.complete"]
    delivery_id: UUID
    correlation_id: UUID
    producer: Literal["aegis-provider-service"]
    provider: Literal["AbuseIPDB"]
    created_at: datetime
    snapshot: InternalBlacklistResponse

    @field_validator("created_at")
    @classmethod
    def validate_created_at(cls, value: datetime) -> datetime:
        validated = require_aware(value)
        assert validated is not None
        return validated

    @model_validator(mode="after")
    def validate_provider_matches_snapshot(self) -> Self:
        if self.provider != self.snapshot.provider:
            raise ValueError("Message provider does not match snapshot provider.")
        return self


class RetryMetadata(BaseModel):
    """Safe retry information included with a rate-limit error."""

    model_config = ConfigDict(extra="forbid")

    retry_after_seconds: StrictInt | None = Field(default=None, ge=0)
    reset_at: datetime | None = None

    @field_validator("reset_at")
    @classmethod
    def validate_reset_at(cls, value: datetime | None) -> datetime | None:
        return require_aware(value)


class ErrorDetail(BaseModel):
    code: StrictStr = Field(min_length=1, max_length=64)
    message: StrictStr = Field(min_length=1, max_length=500)
    request_id: StrictStr = Field(min_length=1, max_length=36)
    retry: RetryMetadata | None = None


class ErrorResponse(BaseModel):
    error: ErrorDetail
