# Weather App

Застосунок демонструє UI-сесії в Redis і асинхронний запис погодних даних
через RabbitMQ. Повна схема та всі потоки описані у
[`docs/architecture.md`](docs/architecture.md).

## Запуск через Docker Compose

```bash
docker compose up --build
```

Відкрийте http://localhost:5000. Compose запускає UI, Proxy, Poller, Backend,
PostgreSQL, Redis і RabbitMQ. Backend одночасно надає HTTP API для читання та
споживає події погоди з RabbitMQ. RabbitMQ Management UI доступний
на http://localhost:15672 (логін/пароль: `admin` / `admin`).

Зупинити сервіси, не видаляючи дані PostgreSQL:

```bash
docker compose down
```

## Перевірка Redis-сесії

1. Відкрийте UI, змініть період графіка, фільтри міст або розгорніть історію.
2. Оновіть сторінку — стан має відновитися.
3. Відкрийте UI в incognito / іншому браузері — це буде окрема сесія з
   незалежними налаштуваннями.

## Перевірка RabbitMQ

Poller за замовчуванням опитує Kyiv, Warsaw і Berlin раз на 15 хвилин.
Після першого циклу в RabbitMQ Management UI з'явиться черга `weather_events`,
а RabbitMQ worker усередині Backend запише події в PostgreSQL. Інтервал можна змінити змінною
`POLL_INTERVAL_SECONDS` у `docker-compose.yml`.

## Vagrant

Vagrant створює окремі VM, але всі application та infrastructure services
працюють усередині Docker-контейнерів. Provisioning-скрипти встановлюють
Docker і Docker Compose, після чого запускають локальний для кожної VM
`docker-compose.yml`. Конфігурація IP-адрес і змінних середовища знаходиться у
[`Vagrantfile`](Vagrantfile).

| VM | Docker-контейнери |
|---|---|
| `db` | `academy-postgres`, `academy-redis`, `academy-rabbitmq` |
| `backend` | `academy-backend` |
| `proxy` | `academy-proxy` |
| `poller` | `academy-poller` |
| `ui` | `academy-ui` |

Compose-файли знаходяться в `infrastructure/`, `backend/`, `proxy/`,
`poller-service/` та `ui-service/`.

```bash
vagrant up
vagrant ssh backend -c "sudo docker ps"
vagrant ssh db -c "sudo docker ps"
```

Docker volumes на VM `db` зберігають PostgreSQL, Redis і RabbitMQ data після
перезапуску або перестворення контейнерів.

## Локальний запуск

Для запуску без Docker потрібні PostgreSQL, Redis і RabbitMQ, після чого кожен
процес запускається зі своєї папки й відповідного `requirements.txt`.
Передайте `REDIS_HOST`, `RABBITMQ_URL`, `DB_HOST`, `PROXY_SERVICE_URL` (для Poller)
та `BACKEND_SERVICE_URL` (для UI) через змінні середовища. `devenv.nix` надає Python-залежності,
але Redis і RabbitMQ він не запускає.
