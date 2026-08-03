import pytest

from app.main import seconds_until_boundary


@pytest.mark.parametrize(
    ("now", "expected"),
    [
        (12 * 3600 + 5 * 60, 0),
        (12 * 3600 + 5 * 60 + 2, 298),
        (12 * 3600 + 9 * 60 + 58, 2),
    ],
)
def test_collector_aligns_to_five_minute_boundaries(now, expected):
    assert seconds_until_boundary(now, 300) == pytest.approx(expected)
