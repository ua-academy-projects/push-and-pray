FROM cgr.dev/chainguard/python:latest-dev@sha256:7b253a0b7cbe886469db59e4cca6d86fffb48d3263d36b374bc0c946c2c5d9dd AS dependencies

USER root
WORKDIR /app

ENV PATH="/opt/venv/bin:${PATH}"

RUN python -m venv /opt/venv
COPY pyproject.toml ./
RUN pip install --disable-pip-version-check --no-cache-dir .

FROM cgr.dev/chainguard/python:latest@sha256:69437de912cc3b5d36a2480b8fb0c3f658f151d8bc1978d19a6412be3a4983d5

WORKDIR /app

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY --from=dependencies /opt/venv /opt/venv
COPY app ./app

USER 65532
EXPOSE 8000
ENTRYPOINT ["/opt/venv/bin/uvicorn"]
CMD ["app.main:app", "--host", "0.0.0.0", "--port", "8000"]
