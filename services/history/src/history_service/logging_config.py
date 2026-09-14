from __future__ import annotations

import logging
import logging.config

HEALTH_PATH = "/health"


class UvicornFields(logging.Filter):
    """Tidy uvicorn's records: request fields as fields, no health probes.

    uvicorn formats its access line from positional args; keeping them as
    separate fields is what lets a log query filter on the status code. Its
    startup messages carry a terminal-colour variant that is noise in JSON.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        record.__dict__.pop("color_message", None)
        if record.name == "uvicorn.access" and isinstance(record.args, tuple):
            if len(record.args) != 5:
                return True
            client, method, path, http_version, status = record.args
            record.client = client
            record.method = method
            record.path = path
            record.http_version = http_version
            record.status = status
            return not str(path).startswith(HEALTH_PATH)
        return True


def configure_logging(level: str) -> None:
    """Log one JSON document per line to stdout, uvicorn's own loggers included.

    Docker records every stderr line as an error, so stdout is deliberate.
    """

    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "filters": {"uvicorn": {"()": UvicornFields}},
            "formatters": {
                "json": {
                    "()": "pythonjsonlogger.json.JsonFormatter",
                    "format": "%(asctime)s %(levelname)s %(name)s %(message)s",
                    "rename_fields": {
                        "asctime": "time",
                        "levelname": "level",
                        "name": "logger",
                    },
                }
            },
            "handlers": {
                "stdout": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                    "formatter": "json",
                    "filters": ["uvicorn"],
                }
            },
            # uvicorn installs its own handlers before the application is
            # imported; route its loggers through the root handler instead.
            "loggers": {
                "uvicorn": {"handlers": [], "propagate": True},
                "uvicorn.error": {"handlers": [], "propagate": True},
                "uvicorn.access": {"handlers": [], "propagate": True},
            },
            "root": {"level": level.upper(), "handlers": ["stdout"]},
        }
    )
