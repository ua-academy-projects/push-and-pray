ARG NODE_IMAGE=node:24.16.0-bookworm-slim
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.11.32
ARG PYTHON_IMAGE=python:3.13.14-slim-bookworm


FROM ${NODE_IMAGE} AS frontend

WORKDIR /build/services/ui/frontend

COPY services/ui/frontend/package.json services/ui/frontend/package-lock.json ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci

COPY services/ui/frontend ./

RUN npm run build


FROM ${UV_IMAGE} AS uv


FROM ${PYTHON_IMAGE} AS builder

COPY --from=uv /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project


FROM ${PYTHON_IMAGE} AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:${PATH}"

RUN groupadd --system --gid 10001 app \
    && useradd \
        --system \
        --uid 10001 \
        --gid app \
        --home-dir /app \
        --shell /usr/sbin/nologin \
        app

WORKDIR /app

COPY --from=builder \
    --chown=app:app \
    /app/.venv \
    ./.venv

COPY --chown=app:app \
    services/ui/backend/src/ui_service \
    ./ui_service

COPY --from=frontend \
    --chown=app:app \
    /build/services/ui/backend/src/ui_service/static \
    ./ui_service/static

USER app

EXPOSE 8080

CMD ["uvicorn", "ui_service.main:app", "--host", "0.0.0.0", "--port", "8080"]