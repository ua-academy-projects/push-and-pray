FROM python:3.14-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build
COPY pyproject.toml ./
COPY src ./src
RUN python -m pip wheel --wheel-dir /wheels .

FROM python:3.14-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --gid 10001 aegis \
    && useradd --uid 10001 --gid aegis --no-create-home --home-dir /app aegis

COPY --from=builder /wheels /wheels
RUN python -m pip install --no-cache-dir /wheels/* \
    && rm -rf /wheels

WORKDIR /app
USER 10001:10001
EXPOSE 8001

CMD ["uvicorn", "provider_service.main:app", "--host", "0.0.0.0", "--port", "8001"]
