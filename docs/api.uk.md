# Довідник API

[English version](api.md)

Публічний Backend: `http://127.0.0.1:8000`. Внутрішній API Fetcher: `http://127.0.0.1:8081`.

## Стан Backend

### `GET /health/live`

Повертає `200`, якщо процес Backend працює.

### `GET /health/ready`

Перевіряє доступність API Fetcher. Повертає `503`, якщо API Fetcher або PostgreSQL недоступні.

## Каталог і поточні курси

### `GET /api/v1/instruments`

Повертає підтримуваний каталог криптовалютних і фіатних пар.

### `GET /api/v1/overview?quote=usd&fiat_quote=UAH`

Повертає головну Bitcoin-картку, топ-10 криптовалют і десять фіатних пар відносно гривні. Звичайний overview може використовувати in-memory cache і не зберігається автоматично.

### `GET /api/v1/rates/current`

Параметри:

- `instruments`: 1–10 ID через кому;
- `refresh`: `false` за замовчуванням.

`refresh=false` дозволяє кеш. `refresh=true` примусово викликає провайдера і ставить успішні результати в RabbitMQ для History.

### `POST /api/v1/rates/refresh`

Програмний endpoint для примусового provider refresh:

```json
{
  "instruments": ["crypto:bitcoin:usd", "fiat:USD:UAH"]
}
```

Він обходить кеш, викликає зовнішній API та повертає `persistence_status`. UI-кнопка «Оновити» цей endpoint не використовує.

### `GET /api/v1/rates/stored-current?instruments=...`

Повертає останнє PostgreSQL-спостереження для 1–10 інструментів через API Fetcher. CoinGecko і Frankfurter не викликаються. Саме цей endpoint використовує кнопка «Оновити» в огляді.

## Капіталізація, історія та backfill

### `GET /api/v1/market-map?period=1d`

Повертає поточну топ-10 капіталізацію CoinGecko і зміну за `1h`, `4h`, `1d`, `7d`, `30d` або `1y`. Результат кешується на 300 секунд.

### `GET /api/v1/rates/history`

Параметри:

- `instruments`: 1–5 ID через кому;
- `from`: обов’язковий RFC3339 timestamp;
- `to`: обов’язковий RFC3339 timestamp;
- `step`: `5m`, `30m`, `1h`, `4h` або `1d`;
- `mode`: `price` або `percent`;
- максимальний проміжок: 366 днів.

Backend не викликає провайдерів. Він отримує series від API Fetcher, який читає PostgreSQL, групує `date_bin` і повертає останнє спостереження кожного бакета. Порожні бакети пропускаються. Відсоткова нормалізація виконується UI.

### `POST /api/v1/rates/backfill`

```json
{
  "instruments": ["crypto:bitcoin:usd", "fiat:USD:UAH"],
  "from_date": "2025-07-17",
  "to_date": "2026-07-17"
}
```

Приймає 1–20 інструментів і проміжок до 366 днів. З RabbitMQ повертає `fetched`, `queued` та `persistence_status`; без RabbitMQ — синхронні `inserted` і `duplicates`.

### `GET /api/v1/requests/history`

Проксіює необроблені PostgreSQL-спостереження:

- `instrument_id`: необов’язковий точний ID;
- `limit`: 1–100, типово 50;
- `cursor`: RFC3339 `next_cursor` попередньої сторінки.

## Формат курсу

```json
{
  "instrument_id": "crypto:bitcoin:usd",
  "kind": "crypto",
  "base": "BTC",
  "quote": "USD",
  "name": "Bitcoin",
  "price": "62860.00",
  "change_1h_percent": "0.25",
  "change_24h_percent": "-1.50",
  "market_cap": "1250000000000",
  "rank": 1,
  "source": "coingecko",
  "source_timestamp": "2026-07-17T09:25:00Z",
  "requested_at": "2026-07-17T09:25:00Z",
  "persistence_status": "queued"
}
```

Decimal-поля передаються рядками для уникнення втрати точності. Необов’язкові значення мають `null`. UI форматує ціни до двох знаків.

## Помилки провайдера

```json
{
  "error": {
    "code": "UPSTREAM_RATE_LIMITED",
    "message": "Rate provider is temporarily unavailable",
    "request_id": "uuid",
    "retry_after_seconds": 30
  }
}
```

Валідаційні та явні FastAPI-помилки можуть використовувати поле `detail`. History-unavailable повертає `503`.

`persistence_status` має значення `queued` після підтвердженої публікації в RabbitMQ, `saved` після HTTP fallback, `failed`, якщо обидва шляхи не спрацювали, або `skipped` для читань без persistence.

## RabbitMQ

Backend публікує persistent JSON-повідомлення в durable direct exchange `rates.events` з routing key `observation.persist`. API Fetcher читає чергу `rates.observations`, надсилає ACK після запису в PostgreSQL, а повторно невдале повідомлення переходить у `rates.observations.dlq`.

## Внутрішній History API

Усі `/internal/v1/*` endpoint потребують `Authorization: Bearer <API_FETCHER_TOKEN>`.

- `POST /internal/v1/observations` — ідемпотентно зберігає одне спостереження.
- `POST /internal/v1/observations/batch` — послідовно зберігає 1–100 спостережень.
- `GET /internal/v1/observations` — повертає cursor-paginated записи.
- `GET /internal/v1/series` — повертає PostgreSQL-часові ряди з обраним кроком.
- `GET /health/live` — перевіряє процес.
- `GET /health/ready` — додатково виконує PostgreSQL ping.

Унікальний індекс `(source, instrument_id, source_timestamp, requested_at)` не дозволяє повторно зберегти той самий знімок, але дозволяє новий знімок наступного п’ятихвилинного циклу.
