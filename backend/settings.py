import os

DB_HOST = os.getenv("DB_HOST", "db.local")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "weather_db")
DB_USER = os.getenv("DB_USER", "weather_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "weather_password")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "db.local")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "weather")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "weather_rabbit_password")
RABBITMQ_VHOST = os.getenv("RABBITMQ_VHOST", "weather")
RABBITMQ_QUEUE = os.getenv("RABBITMQ_QUEUE", "weather_updates")
