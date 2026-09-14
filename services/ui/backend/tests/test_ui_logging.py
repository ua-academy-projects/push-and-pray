import io
import json
import logging

import pytest

from ui_service.logging_config import UvicornFields, configure_logging


def access_record(path: str, status: int = 200) -> logging.LogRecord:
    return logging.LogRecord(
        name="uvicorn.access",
        level=logging.INFO,
        pathname=__file__,
        lineno=0,
        msg='%s - "%s %s HTTP/%s" %d',
        args=("10.0.1.5:4123", "GET", path, "1.1", status),
        exc_info=None,
    )


def test_access_record_is_unpacked_into_fields() -> None:
    record = access_record("/v1/observations?limit=10", 200)

    assert UvicornFields().filter(record) is True
    assert record.method == "GET"
    assert record.path == "/v1/observations?limit=10"
    assert record.status == 200
    assert record.client == "10.0.1.5:4123"


def test_health_probes_are_dropped() -> None:
    assert UvicornFields().filter(access_record("/health")) is False


def test_other_records_pass_through() -> None:
    record = logging.LogRecord("ui_service", logging.INFO, __file__, 0, "hi", (), None)

    assert UvicornFields().filter(record) is True


def test_colour_variant_is_dropped() -> None:
    record = logging.LogRecord("uvicorn.error", logging.INFO, __file__, 0, "up", (), None)
    record.color_message = "\x1b[1mup\x1b[0m"

    assert UvicornFields().filter(record) is True
    assert not hasattr(record, "color_message")


@pytest.fixture
def captured_stdout(monkeypatch: pytest.MonkeyPatch) -> io.StringIO:
    buffer = io.StringIO()
    monkeypatch.setattr("sys.stdout", buffer)
    configure_logging("INFO")
    yield buffer
    logging.getLogger().handlers.clear()


def test_lines_are_json_with_level_and_message(captured_stdout: io.StringIO) -> None:
    logging.getLogger("ui_service.test").warning("queue %s is slow", "price_observations")

    entry = json.loads(captured_stdout.getvalue().strip())

    assert entry["level"] == "WARNING"
    assert entry["logger"] == "ui_service.test"
    assert entry["message"] == "queue price_observations is slow"
    assert "time" in entry


def test_uvicorn_access_lines_carry_request_fields(captured_stdout: io.StringIO) -> None:
    record = access_record("/v1/instruments", 404)
    logging.getLogger("uvicorn.access").handle(record)
    logging.getLogger("uvicorn.access").handle(access_record("/health"))

    lines = captured_stdout.getvalue().strip().splitlines()

    assert len(lines) == 1
    entry = json.loads(lines[0])
    assert entry["path"] == "/v1/instruments"
    assert entry["status"] == 404
