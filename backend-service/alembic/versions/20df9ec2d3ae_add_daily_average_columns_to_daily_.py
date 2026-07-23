"""add daily average columns to daily_weather

Revision ID: 20df9ec2d3ae
Revises: 2d99cab83354
Create Date: 2026-07-23 18:42:15.132766

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20df9ec2d3ae'
down_revision: Union[str, Sequence[str], None] = '2d99cab83354'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Adds the six average_* columns as nullable, backfills every existing daily_weather row
    from its matching hourly_weather rows (hourly-derived average where at least one hourly
    row exists for that location+local-date, else a (min+max)/2 fallback), then locks down
    NOT NULL on the three columns that are always computable (average_temperature,
    average_temperature_method, average_apparent_temperature). average_humidity/
    average_wind_speed/average_cloud_cover have no fallback source and stay nullable
    permanently -- a day with no hourly data at all just has no value for them.

    A hand-written data migration, not a one-off script: it needs to run exactly once, in the
    same deploy that adds the columns, against whatever real data already exists -- Alembic's
    upgrade path is the natural place for that, not a separate throwaway script that could be
    forgotten or run against the wrong database."""
    op.add_column('daily_weather', sa.Column('average_temperature', sa.Float(), nullable=True))
    op.add_column('daily_weather', sa.Column('average_temperature_method', sa.Enum('hourly', 'min_max_fallback', name='averagetemperaturemethod', native_enum=False, length=20), nullable=True))
    op.add_column('daily_weather', sa.Column('average_apparent_temperature', sa.Float(), nullable=True))
    op.add_column('daily_weather', sa.Column('average_humidity', sa.Float(), nullable=True))
    op.add_column('daily_weather', sa.Column('average_wind_speed', sa.Float(), nullable=True))
    op.add_column('daily_weather', sa.Column('average_cloud_cover', sa.Float(), nullable=True))

    # Step 1: backfill every daily_weather row that has at least one matching hourly_weather
    # row (joined on location + local calendar date, converting hourly_weather's UTC-stored
    # timestamp to the location's own timezone -- this app has one location, but the join
    # stays correct even if that ever changes).
    op.execute(
        """
        UPDATE daily_weather dw
        SET
            average_temperature = h.avg_temp,
            average_temperature_method = 'hourly',
            average_apparent_temperature = h.avg_apparent,
            average_humidity = h.avg_humidity,
            average_wind_speed = h.avg_wind,
            average_cloud_cover = h.avg_cloud
        FROM (
            SELECT
                hw.location_id,
                (hw.weather_time AT TIME ZONE l.timezone)::date AS local_date,
                AVG(hw.temperature) AS avg_temp,
                AVG(hw.apparent_temperature) AS avg_apparent,
                AVG(hw.humidity) AS avg_humidity,
                AVG(hw.wind_speed) AS avg_wind,
                AVG(hw.cloud_cover) AS avg_cloud
            FROM hourly_weather hw
            JOIN locations l ON l.id = hw.location_id
            GROUP BY hw.location_id, local_date
        ) h
        WHERE h.location_id = dw.location_id AND h.local_date = dw.weather_date
        """
    )

    # Step 2: any row the first UPDATE didn't touch (no hourly data at all for that date)
    # falls back to (min+max)/2 -- average_humidity/wind/cloud stay NULL, no fallback exists.
    op.execute(
        """
        UPDATE daily_weather
        SET
            average_temperature = (temperature_min + temperature_max) / 2.0,
            average_temperature_method = 'min_max_fallback',
            average_apparent_temperature = (apparent_temperature_min + apparent_temperature_max) / 2.0
        WHERE average_temperature IS NULL
        """
    )

    op.alter_column('daily_weather', 'average_temperature', nullable=False)
    op.alter_column('daily_weather', 'average_temperature_method', nullable=False)
    op.alter_column('daily_weather', 'average_apparent_temperature', nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('daily_weather', 'average_cloud_cover')
    op.drop_column('daily_weather', 'average_wind_speed')
    op.drop_column('daily_weather', 'average_humidity')
    op.drop_column('daily_weather', 'average_apparent_temperature')
    op.drop_column('daily_weather', 'average_temperature_method')
    op.drop_column('daily_weather', 'average_temperature')
