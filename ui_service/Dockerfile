FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd --create-home --shell /usr/sbin/nologin wildlife

COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY ui_service ./ui_service

USER wildlife

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=4)"

CMD ["python", "-m", "ui_service.app"]
