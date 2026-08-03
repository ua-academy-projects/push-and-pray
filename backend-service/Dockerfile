FROM python:3.12-slim

WORKDIR /backend

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY migrations/ ./migrations/

EXPOSE 5001

CMD ["python3", "app.py"]