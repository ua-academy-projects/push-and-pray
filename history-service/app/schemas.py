from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class HistoryRecordCreate(BaseModel):
    """Payload used to create a history record."""

    request_type: str = Field(
        min_length=1,
        max_length=50,
        examples=["air_quality"],
    )

    query_parameters: dict[str, Any]

    response_data: dict[str, Any] | list[Any]

    result_count: int = Field(
        ge=0,
        examples=[1],
    )

    source: str = Field(
        min_length=1,
        max_length=50,
        examples=["open-meteo"],
    )

    source_status_code: int = Field(
        ge=100,
        le=599,
        examples=[200],
    )

    @field_validator("request_type", "source")
    @classmethod
    def normalize_non_blank_strings(cls, value: str) -> str:
        normalized_value = value.strip()

        if not normalized_value:
            raise ValueError("must not be blank")

        return normalized_value


class HistoryRecordCreated(BaseModel):
    """Response returned after creating a record."""

    id: int
    created_at: datetime
    message: str


class HistoryRecordSummary(BaseModel):
    """Short representation used in history lists."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    request_type: str
    query_parameters: dict[str, Any]
    result_count: int
    source: str
    source_status_code: int


class HistoryRecordDetail(HistoryRecordSummary):
    """Complete history record."""

    response_data: dict[str, Any] | list[Any]


class HistoryRecordList(BaseModel):
    """Paginated history response."""

    items: list[HistoryRecordSummary]
    total: int
    limit: int
    offset: int