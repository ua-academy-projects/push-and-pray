FROM python:3.12-slim

WORKDIR /provider

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5002

CMD ["python3", "app.py"]
