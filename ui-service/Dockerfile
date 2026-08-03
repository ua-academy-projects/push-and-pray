FROM python:3.12-slim

WORKDIR /ui

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY static/ ./static/
COPY templates/ ./templates/

EXPOSE 5000

CMD ["python3", "app.py"]