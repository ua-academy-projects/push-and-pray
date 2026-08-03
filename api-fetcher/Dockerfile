FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd --create-home --uid 10001 rateboard
WORKDIR /app
COPY pyproject.toml ./
RUN pip install --disable-pip-version-check --no-cache-dir .
COPY app ./app

USER rateboard
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
