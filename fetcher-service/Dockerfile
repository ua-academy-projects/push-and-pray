# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder

WORKDIR /build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip \
    && pip install -r requirements.txt gunicorn==23.0.0

FROM python:3.12-slim AS runtime

RUN groupadd --system app && useradd --system --gid app --no-create-home --home-dir /app app

WORKDIR /app
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY --from=builder /opt/venv /opt/venv
COPY app ./app

RUN chown -R app:app /app
USER app

EXPOSE 8002

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8002/health', timeout=3)"

# --workers is hardcoded to 1, not configurable: this service runs an in-process
# APScheduler (app/scheduler/weather_scheduler.py). More than one worker process
# would each run its own scheduler and cause duplicate Open-Meteo syncs -- see
# docs/architecture.md §13 decisions 9-10.
CMD ["gunicorn", "app.main:app", \
     "-k", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8002", \
     "--workers", "1", \
     "--timeout", "30", \
     "--graceful-timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
