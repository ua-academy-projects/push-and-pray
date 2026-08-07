"""PostgreSQL operations owned by the combined Backend+History service."""

import os

import psycopg
from psycopg.rows import dict_row


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://wildlife_user:wildlife_password@127.0.0.1:5432/wildlife",
)


def get_connection():
    """Open a PostgreSQL connection returning rows as dictionaries."""

    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


def create_tables() -> None:
    """Create or upgrade the two tables required by the application."""

    sql = """
        CREATE TABLE IF NOT EXISTS species_observation_state (
            scientific_name VARCHAR(200) PRIMARY KEY,
            taxon_key BIGINT,
            observation_count INTEGER NOT NULL
                CHECK (observation_count >= 0),
            checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        ALTER TABLE species_observation_state
        ADD COLUMN IF NOT EXISTS taxon_key BIGINT;

        CREATE TABLE IF NOT EXISTS observation_changes (
            id BIGSERIAL PRIMARY KEY,
            scientific_name VARCHAR(200) NOT NULL,
            previous_count INTEGER NOT NULL
                CHECK (previous_count >= 0),
            current_count INTEGER NOT NULL
                CHECK (current_count >= 0),
            change_amount INTEGER NOT NULL,
            changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        CREATE INDEX IF NOT EXISTS observation_changes_date_idx
        ON observation_changes (changed_at DESC);
    """

    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)


def save_observation(
    scientific_name: str,
    taxon_key: int,
    current_count: int,
) -> dict:
    """Save the first state or record a real count change."""

    insert_state_sql = """
        INSERT INTO species_observation_state
            (scientific_name, taxon_key, observation_count)
        VALUES (%s, %s, %s)
        ON CONFLICT (scientific_name) DO NOTHING
        RETURNING scientific_name
    """
    select_sql = """
        SELECT observation_count
        FROM species_observation_state
        WHERE scientific_name = %s
        FOR UPDATE
    """
    update_sql = """
        UPDATE species_observation_state
        SET taxon_key = %s, observation_count = %s, checked_at = NOW()
        WHERE scientific_name = %s
    """
    insert_change_sql = """
        INSERT INTO observation_changes
            (scientific_name, previous_count, current_count, change_amount)
        VALUES (%s, %s, %s, %s)
        RETURNING id, scientific_name, previous_count, current_count,
                  change_amount, changed_at
    """

    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                insert_state_sql,
                (scientific_name, taxon_key, current_count),
            )
            if cursor.fetchone() is not None:
                return {"status": "baseline_created", "change": None}

            cursor.execute(select_sql, (scientific_name,))
            previous_count = cursor.fetchone()["observation_count"]
            cursor.execute(
                update_sql,
                (taxon_key, current_count, scientific_name),
            )

            if previous_count == current_count:
                return {"status": "unchanged", "change": None}

            change_amount = current_count - previous_count
            cursor.execute(
                insert_change_sql,
                (
                    scientific_name,
                    previous_count,
                    current_count,
                    change_amount,
                ),
            )
            return {"status": "changed", "change": cursor.fetchone()}


def get_changes(limit: int = 10) -> list[dict]:
    """Return only real changes, never a list of user requests."""

    sql = """
        SELECT id, scientific_name, previous_count, current_count,
               change_amount, changed_at
        FROM observation_changes
        ORDER BY changed_at DESC, id DESC
        LIMIT %s
    """
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql, (limit,))
            return cursor.fetchall()


def get_tracked_species() -> list[dict]:
    """Return species that the scheduled Fetcher should refresh."""

    sql = """
        SELECT scientific_name, taxon_key
        FROM species_observation_state
        WHERE taxon_key IS NOT NULL
        ORDER BY scientific_name
    """
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)
            return cursor.fetchall()


def database_is_ready() -> bool:
    """Check that Backend can execute a query in PostgreSQL."""

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                return cursor.fetchone() is not None
    except psycopg.Error:
        return False
