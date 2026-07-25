# Архітектура

## Компоненти

| Компонент | Протокол / порт | Відповідальність |
|---|---|---|
| **UI Service** | HTTP 5000 | Віддає UI, створює анонімну browser-session і зберігає її UI-стан у Redis. |
| **Redis** | Redis 6379 | Тимчасове сховище `session:<UUID>` з TTL 24 години. Не містить бізнес-даних. |
| **Poller** | HTTP client | За розкладом запускає отримання погоди для контрольованих міст. |
| **Proxy Service** | HTTP 5001, AMQP client | Викликає Open-Meteo, читає історію через Backend і публікує нові погодні події в RabbitMQ. |
| **RabbitMQ** | AMQP 5672 | Durable queue `weather_events` для асинхронного передавання подій. |
| **History Consumer** | AMQP consumer, SQL client | Споживає `weather_events`, підтверджує повідомлення після успішного запису в PostgreSQL. |
| **Backend Service** | HTTP 5002, SQL client | Read API для історії та погодинного прогнозу. |
| **PostgreSQL** | SQL 5432 | Постійно зберігає історію погоди та погодинний прогноз. |

## Потоки даних

### UI-сесія

1. Браузер відкриває UI Service. UI створює випадковий `session_id` у cookie,
   якщо його ще немає.
2. UI читає або записує `session:<session_id>` у Redis.
3. Стан містить `graph_period`, список міст у `filters` та `history_expanded`.
   Тому refresh відновлює налаштування саме цього браузера без автентифікації.

### Отримання та асинхронне збереження погоди

1. Poller викликає `GET /api/current?city=...` у Proxy.
2. Proxy викликає Open-Meteo Geocoding та Forecast API через HTTPS.
3. Proxy публікує durable AMQP-повідомлення `weather_current` і
   `weather_hourly` до черги RabbitMQ `weather_events`.
4. History Consumer споживає повідомлення і записує дані в PostgreSQL.
   Повідомлення підтверджується (`ack`) лише після commit; при помилці воно
   повертається до черги.

### Читання історії

`Browser → UI → Proxy → Backend → PostgreSQL` використовує синхронний HTTP
лише для читання. Це не замінює асинхронний запис через RabbitMQ.

## Надійність черги

- Черга оголошена як `durable`.
- Повідомлення мають `delivery_mode=2`.
- Producer очікує publisher confirm; якщо RabbitMQ недоступний, Proxy повертає
  `503`, а не повідомляє про успішне збереження.
- Consumer встановлює `prefetch_count=1`, робить `ack` після успішного запису
  або `nack(requeue=True)` при помилці.
