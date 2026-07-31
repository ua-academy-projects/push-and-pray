# Архітектура

## Компоненти

| Компонент | Протокол / порт | Відповідальність |
|---|---|---|
| **UI Service** | HTTP 5000, HTTP client | Віддає UI, зберігає анонімну UI-сесію в Redis і читає погодні дані безпосередньо з Backend. |
| **Redis** | Redis 6379 | Тимчасове сховище `session:<UUID>` з TTL 24 години. Не містить бізнес-даних. |
| **Poller** | HTTP client | За розкладом запускає отримання погоди для контрольованих міст. |
| **Proxy Service / Weather Fetcher** | HTTP 5001, AMQP client | Приймає запуск лише від Poller, викликає Open-Meteo і публікує нові погодні події в RabbitMQ. |
| **RabbitMQ** | AMQP 5672 | Durable queue `weather_events` для асинхронного передавання подій. |
| **Backend / History Service** | HTTP 5002, AMQP consumer, SQL client | Read API для історії та погодинного прогнозу; споживає `weather_events` і записує їх у PostgreSQL. |
| **PostgreSQL** | SQL 5432 | Постійно зберігає історію погоди та погодинний прогноз. |

## Розміщення у Vagrant

Vagrant відповідає за VM і дві мережі. Кожен сервіс запускається в
Docker-контейнері всередині відповідної VM. Provisioning-скрипт встановлює
`docker.io` та Compose plugin, а потім виконує `docker compose up -d`:

- **Public LAN** `192.168.1.0/27` — доступ інших пристроїв локальної мережі,
  зокрема до UI на `192.168.1.19:5000`.
- **Private libvirt** `192.168.56.0/24` — керування з хоста; SSH aliases
  `db`, `backend`, `proxy`, `poller`, `ui` використовують саме ці адреси.
  Це обходить обмеження macvtap, через яке host не може напряму підключатися
  до VM через public adapter.

| VM | Контейнер | Порти на VM |
|---|---|---|
| `ui` | `academy-ui` | `5000:5000` |
| `poller` | `academy-poller` | немає |
| `proxy` | `academy-proxy` | `5001:5001` |
| `backend` | `academy-backend` | `5002:5002` |
| `db` | `academy-postgres` | `5432:5432` |
| `db` | `academy-redis` | `6379:6379` |
| `db` | `academy-rabbitmq` | `5672:5672`, `15672:15672` |

Контейнери використовують Docker host network усередині своєї VM. Це прибирає
зайвий nested NAT між bridged VM і Docker та дозволяє звертатися до сервісів за
статичними IP VM із `Vagrantfile`. Дані infrastructure containers зберігаються
у named Docker volumes.

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
4. RabbitMQ worker усередині Backend/History Service споживає повідомлення і
   записує дані в PostgreSQL.
   Повідомлення підтверджується (`ack`) лише після commit; при помилці воно
   повертається до черги.

Колишні синхронні `POST /history` та `POST /history/hourly` видалені. Таким
чином єдиний write-path між Proxy і Backend проходить через RabbitMQ.

### Читання історії

`Browser → UI → Backend → PostgreSQL` використовує синхронний HTTP лише для
читання. UI не звертається до Proxy/Weather Fetcher. RabbitMQ не потрібен для
request/response-запитів читання.

## Надійність черги

- Черга оголошена як `durable`.
- Повідомлення мають `delivery_mode=2`.
- Producer очікує publisher confirm; якщо RabbitMQ недоступний, Proxy повертає
  `503`, а не повідомляє про успішне збереження.
- Consumer встановлює `prefetch_count=1`, робить `ack` після успішного запису
  або `nack(requeue=True)` при помилці.
