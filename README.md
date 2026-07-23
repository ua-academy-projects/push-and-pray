# DevOps Academy — : Weather App

Проста застосунок з трьох сервісів + база даних, побудована за архітектурою з
завдання: **UI → Proxy → Backend → PostgreSQL**, а Proxy додатково
звертається до публічного **Open-Meteo API** (безкоштовне, без API-ключа).

Детальний опис архітектури — у [`docs/architecture.md`](docs/architecture.md).

## Структура проєкту

```
project-root/
  ui-service/         # Flask, порт 5000
  proxy/               # Flask, порт 5001
  backend/             # Flask, порт 5002, доступ до БД
  poller-service/       # окремий фоновий процес (без HTTP-порту)
  docs/
  docker-compose.yml
  README.md
```

## Вимоги

- Python 3.10+
- PostgreSQL (локально встановлений або запущений будь-яким зручним способом)

## Швидкий старт через devenv.sh (опційно)

Якщо встановлено [devenv.sh](https://devenv.sh/getting-started/), Python-оточення
та PostgreSQL піднімаються автоматично — окремо venv і `docker run` для БД
робити не потрібно:

```bash
devenv shell    # створює venv, ставить залежності, готує postgres
devenv up       # запускає postgres + усі 3 Flask-сервіси одночасно
```

БД `devops_academy` та роль `devops`/`devops` створюються автоматично
(`initialScript` у `devenv.nix`). Після `devenv up` відкрийте
**http://localhost:5000**.

Якщо devenv.sh не використовується — далі стандартний шлях через venv:

## 1. Підготовка бази даних

Створіть базу та користувача (приклад для `psql`):

```sql
CREATE DATABASE devops_academy;
CREATE USER devops WITH PASSWORD 'devops';
GRANT ALL PRIVILEGES ON DATABASE devops_academy TO devops;
```

Схему таблиці (`backend/db.sql`) сервіс створює автоматично при старті —
окремо запускати нічого не потрібно.

> Якщо немає локального PostgreSQL, найшвидший спосіб для тестування —
> запустити лише базу в контейнері:
> `docker run -d --name devops-pg -e POSTGRES_DB=devops_academy -e POSTGRES_USER=devops -e POSTGRES_PASSWORD=devops -p 5432:5432 postgres:16`
> (Docker тут використовується лише як зручність для БД, а не як частина цього завдання.)

## 2. Встановлення залежностей

Для кожного сервісу — окреме віртуальне середовище (рекомендовано):

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cd ..

cd proxy
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cd ..

cd ui-service
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cd ..

cd poller-service
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cd ..
```

## 3. Змінні середовища (опційно, є значення за замовчуванням)

**backend-service**
| Змінна | За замовчуванням |
|---|---|
| `DB_HOST` | localhost |
| `DB_PORT` | 5432 |
| `DB_NAME` | devops_academy |
| `DB_USER` | devops |
| `DB_PASSWORD` | devops |
| `PORT` | 5002 |

**proxy-service**
| Змінна | За замовчуванням |
|---|---|
| `BACKEND_SERVICE_URL` | http://localhost:5002 |
| `PORT` | 5001 |

**ui-service**
| Змінна | За замовчуванням |
|---|---|
| `PROXY_SERVICE_URL` | http://localhost:5001 |
| `PORT` | 5000 |

## 4. Запуск (3 окремі термінали)

```bash
# Термінал 1
cd backend && source venv/bin/activate && python backend.py

# Термінал 2
cd proxy && source venv/bin/activate && python proxy.py

# Термінал 3
cd ui-service && source venv/bin/activate && python app.py
```

Відкрийте у браузері: **http://localhost:5000**

## 5. Як користуватись

UI навмисно **не дозволяє** користувачу ініціювати виклик публічного API -
єдине джерело нових даних - фоновий Poller (розділ 6 нижче). У браузері
доступна лише одна дія:

1. Натисніть "Оновити список", щоб побачити накопичену Backend Service
   історію (Backend Service → Proxy → UI). Нові записи з'являються
   самі, у міру того, як Poller періодично оновлює дані по містах зі
   списку `WATCHED_CITIES`.

## 6. Автономне оновлення (обов'язковий спосіб отримати нові дані)

Крім оновлення по кліку, є окремий процес `poller-service/poller.py`
(окрема папка, окремий Dockerfile, мінімум залежностей), який сам, за
таймером, оновлює дані для списку міст (`WATCHED_CITIES`, за
замовчуванням `Kyiv,Warsaw,Berlin`) кожні `POLL_INTERVAL_SECONDS`
(за замовчуванням 900 = 15 хв) - навіть якщо ніхто не відкриває UI.

Через devenv (`devenv up`) чи Docker Compose (`docker compose up`) він
запускається автоматично разом з рештою. Вручну:

```bash
cd poller-service && source venv/bin/activate && python poller.py
```

Детальніше - у [`docs/architecture.md`](docs/architecture.md#автономне-оновлення-даних-poller).

## 7. Запуск через Docker (опційно)

Кожен сервіс має власний `Dockerfile`, а `docker-compose.yml` у корені
проєкту піднімає все разом (Postgres + 3 сервіси + поллер):

```bash
docker compose up --build
```

Відкрий **http://localhost:5000**. Дані Postgres зберігаються в іменованому
томі `pgdata` між перезапусками.

Важливо: **всередині Docker-мережі сервіси звертаються один до одного за
іменем сервіса з `docker-compose.yml`**, а не за `localhost` (наприклад,
`http://backend-service:5002`, `DB_HOST=postgres-db`) - це вже налаштовано в
змінних середовища всередині `docker-compose.yml`, нічого міняти не
потрібно.

Зупинити й прибрати контейнери (том з даними лишається):
```bash
docker compose down
```

## Доступ до UI з локальної мережі через Vagrant

У Vagrant bridge-мережу має лише VM `ui`; Backend, Proxy та БД лишаються у
приватній мережі. Після запуску UI отримає IP від DHCP вашого роутера, тому
сторінка буде доступна з інших пристроїв у тій самій локальній мережі за
адресою `http://<IP-UI>:5000`.

Для хоста з інтерфейсом, відмінним від `enp2s0`, вкажіть його перед запуском:

```bash
BRIDGE_DEVICE=wlp2s0 vagrant up ui
```

IP UI можна подивитись командою `vagrant ssh ui -c "hostname -I"`. Якщо на VM
увімкнений firewall, дозвольте TCP-порт 5000.

## Публічне API

Використано [Open-Meteo](https://open-meteo.com/) — безкоштовне, без реєстрації
та без API-ключа:
- Geocoding API — перетворення назви міста на координати
- Forecast API — поточна погода за координатами

## Межі відповідальності (коротко)

- **UI Service** — лише відображення, ніколи не звертається до публічного API чи БД напряму.
- **Proxy Service** — єдина точка виклику зовнішнього API та оркестрації потоку даних.
- **Backend Service** — єдина точка доступу до PostgreSQL.

Це навмисно просто: контейнеризація, Kubernetes, CI/CD та хмарний деплой —
предмет наступних завдань (див. `docs/architecture.md`).
