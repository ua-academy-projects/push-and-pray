# syntax=docker/dockerfile:1

# ---- builder: compile the venv in a throwaway layer with build toolchain ----
FROM python:3.12-slim AS builder

WORKDIR /build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip \
    && pip install -r requirements.txt gunicorn==23.0.0

# ---- runtime: slim image, no compiler, non-root user ----
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

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=3)"

# API and RabbitMQ consumer both run in this one process -- see the lifespan in app/main.py.
# Pinned to a single gunicorn worker: each worker process would start its own independent
# consumer task, so >1 worker would mean multiple concurrent consumers on the same queues.
CMD ["gunicorn", "app.main:app", \
     "-k", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "1", \
     "--timeout", "30", \
     "--graceful-timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
