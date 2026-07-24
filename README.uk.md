# Rateboard

[English version](README.md)

Rateboard — трисервісний застосунок для перегляду криптовалютних і фіатних курсів, створений для DevOps Academy Assignment 1.

```text
Браузер → UI (HTML/CSS/JS) → Backend (Python/FastAPI) → CoinGecko / Frankfurter
                                  │
                                  ├→ RabbitMQ → History (Go) → PostgreSQL
                                  └→ History HTTP (читання та fallback запису)
```

Браузер отримує прикладні дані тільки від Backend. Backend відповідає за інтеграцію із зовнішніми API, нормалізацію та координацію. API Fetcher — єдиний компонент, який напряму працює з PostgreSQL.

## Можливості

- Головна картка Bitcoin/USD і довільні картки порівняння.
- Топ-10 криптовалют зі змінами за годину/день і семиденними мініграфіками.
- Десять фіатних пар відносно гривні.
- Усі курси в інтерфейсі округлюються до двох знаків без втрати точності у БД.
- Динамічні графіки до п’яти інструментів у режимах ціни або відсоткової зміни.
- Незалежний вибір періоду даних (`1d`, `7d`, `30d`, `90d`, `1y`) та кроку (`5m`, `30m`, `1h`, `4h`, `1d`).
- Графіки читають історію з PostgreSQL і автоматично оновлюються кожні п’ять хвилин.
- Карти капіталізації CoinGecko, масштабування графіків, підказки та PDF-експорт.
- Світла біло-зелена й темна темно-сіро-зелена теми.
- Фоновий збирач даних із запуском на точних п’ятихвилинних межах.

## Вимоги

- Python 3.12+
- Go 1.23+
- PostgreSQL 16+
- RabbitMQ 4+
- `psql`, `pg_isready`, `curl`
- браузер та інтернет для зовнішніх API і CDN-залежностей графіків

## Перше налаштування

```bash
cp .env.example .env
```

У `.env` встановіть унікальний `API_FETCHER_TOKEN`. `COINGECKO_API_KEY` рекомендований для вищих лімітів. Файл `.env` та файли API-ключів не можна комітити.

Типова адреса БД:

```text
postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable
```

## Автоматичний запуск

```bash
./scripts/start-all.sh
```

Скрипт:

1. завантажує `.env` і перевіряє залежності;
2. перевіряє PostgreSQL і RabbitMQ та за можливості запускає Homebrew-сервіси;
3. застосовує міграції `001_init.sql`, `002_sampling.sql` і `003_backfill_timestamps.sql`;
4. запускає API Fetcher;
5. створює Python virtualenv за потреби та запускає Backend;
6. запускає статичний UI;
7. записує логи в `.run/` і коректно завершує сервіси після `Ctrl+C`.

Адреси:

- UI: `http://127.0.0.1:3000`
- Backend Swagger: `http://127.0.0.1:8000/docs`
- Backend health: `http://127.0.0.1:8000/health/live`
- API Fetcher readiness: `http://127.0.0.1:8081/health/ready`

Щоб зупинити сервіси Rateboard і звільнити порти `3000`, `8000`, `8081`:

```bash
./scripts/stop-all.sh
```

PostgreSQL і RabbitMQ при цьому продовжують працювати як інфраструктурні залежності.

## Ручний запуск

Порядок: PostgreSQL → RabbitMQ → History → Backend → UI.

RabbitMQ доставляє нормалізовані спостереження від Backend до API Fetcher через durable exchange `rates.events` і чергу `rates.observations`. API Fetcher підтверджує повідомлення лише після запису в PostgreSQL; повторно невдале повідомлення переходить у `rates.observations.dlq`. Якщо публікація недоступна, Backend використовує захищений HTTP endpoint API Fetcher як fallback.

```bash
set -a; source .env; set +a
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/001_init.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/002_sampling.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/003_backfill_timestamps.sql
```

```bash
cd api-fetcher
go mod download
go run ./cmd/server
```

```bash
cd backend-service
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

```bash
cd ui-service/public
python3 -m http.server 3000 --bind 127.0.0.1
```

## Збирання даних

Backend запускає колектор на абсолютних межах `:00`, `:05`, `:10`, `:15` тощо:

```env
COLLECTOR_ENABLED=true
COLLECTOR_INTERVAL_SECONDS=300
```

Кожен цикл запитує 20 налаштованих інструментів і передає успішні результати до API Fetcher. Для кожного циклу використовується вирівняний `requested_at`. Frankfurter може повертати однакове денне значення, але PostgreSQL усе одно зберігає окремий п’ятихвилинний знімок.

Кнопки «Оновити» в огляді та історії читають дані з PostgreSQL. Вони не викликають CoinGecko або Frankfurter.

## Історичне наповнення

```bash
./scripts/backfill-year.sh
```

Backfill використовує рідну деталізацію провайдерів. Він не створює штучних п’ятихвилинних точок за періоди, коли колектор не працював.

## Тести

```bash
cd backend-service && .venv/bin/pytest -q
cd api-fetcher && go test ./...
node --test ui-service/tests/*.test.js
bash -n scripts/start-all.sh scripts/backfill-year.sh
```

## Документація

- [Архітектура українською](docs/architecture.uk.md)
- [API українською](docs/api.uk.md)
- [Відповідність завданню українською](docs/assignment-compliance.uk.md)
- [Шпаргалка для захисту](docs/defense-guide.md)
