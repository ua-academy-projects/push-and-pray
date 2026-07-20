-- Database schema for the Air Quality History Service.
-- Run this script while connected to the application database.

CREATE TABLE IF NOT EXISTS history_records (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    request_type VARCHAR(50) NOT NULL,

    query_parameters JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    response_data JSONB NOT NULL,

    result_count INTEGER NOT NULL
        DEFAULT 0,

    source VARCHAR(50) NOT NULL,

    source_status_code SMALLINT NOT NULL,

    CONSTRAINT history_records_request_type_not_blank
        CHECK (length(trim(request_type)) > 0),

    CONSTRAINT history_records_source_not_blank
        CHECK (length(trim(source)) > 0),

    CONSTRAINT history_records_result_count_non_negative
        CHECK (result_count >= 0),

    CONSTRAINT history_records_source_status_code_valid
        CHECK (source_status_code BETWEEN 100 AND 599)
);


CREATE INDEX IF NOT EXISTS idx_history_records_created_at
    ON history_records (created_at DESC);


CREATE INDEX IF NOT EXISTS idx_history_records_request_type
    ON history_records (request_type);