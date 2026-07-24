# Weather App

Weather App автоматично збирає погоду для Надвірної, зберігає історію
в PostgreSQL і показує останнє вимірювання та погодинний прогноз
температури.

## Архітектура

```text
Browser -> UI Service -> Backend Service -> Provider Service -> Open-Meteo
                              |
                              +-> PostgreSQL
```

- `ui-service` віддає сторінку й проксіює браузерні API-запити лише до
  `backend-service`;
- `backend-service` містить бізнес-логіку, планувальник, SQL і API для UI;
- `provider-service` викликає та нормалізує відповідь Open-Meteo, але не
  має доступу до бази даних;
- PostgreSQL доступний лише для `backend-service`.

Поточна погода збирається кожні 30 хвилин. Оновлення сторінки раз на
60 секунд лише читає вже збережені дані та не викликає Open-Meteo.
Backend перевіряє необхідність оновлення прогнозу кожні 15 хвилин, але
після успішного отримання не викликає Provider повторно протягом
24 годин. Час останнього успішного оновлення та 24 погодинні точки
зберігаються в PostgreSQL, тому цей інтервал переживає перезапуск
застосунку.

## Структура

```text
weather-app/
├── backend-service/
├── provider-service/
├── providers/
│   ├── common.sh
│   ├── backend.sh
│   ├── database.sh
│   ├── provider.sh
│   └── ui.sh
├── ui-service/
├── docker-compose.yml
└── Vagrantfile
```

## Запуск через Docker Compose

Потрібні Docker і Docker Compose.

```bash
docker compose up -d --build
docker compose ps
```

Відкрити на MacBook:

```text
http://localhost:8080
```

Назовні публікується тільки UI на порту `8080`. Порти backend (`5001`),
provider (`5002`) і PostgreSQL (`5432`) залишаються у внутрішній мережі
Compose.

Перевірка UI та всього публічного ланцюжка:

```bash
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8080/api/weather
curl -fsS http://localhost:8080/api/forecast
curl -fsS http://localhost:8080/api/history
```

Перевірка внутрішніх health endpoints:

```bash
docker compose exec provider-service \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:5002/health').read().decode())"

docker compose exec backend-service \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:5001/health').read().decode())"
```

Логи й зупинка:

```bash
docker compose logs -f
docker compose logs -f backend-service provider-service
docker compose down
```

Щоб разом із контейнерами видалити збережені дані:

```bash
docker compose down -v
```

## Запуск через Vagrant і VMware Fusion

Потрібні Vagrant, VMware Fusion і Vagrant VMware Utility/provider.

```bash
vagrant validate
vagrant up --provider=vmware_desktop
```

Повторне налаштування всіх машин:

```bash
vagrant provision
```

Vagrant створює чотири машини у приватній мережі:

| Компонент | Приватна адреса | Порт |
|---|---:|---:|
| UI Service | `192.168.56.10` | `5000` |
| Backend Service | `192.168.56.11` | `5001` |
| Provider Service | `192.168.56.12` | `5002` |
| PostgreSQL | `192.168.56.13` | `5432` |

Тільки UI має forwarded port: гостьовий `5000` прив’язаний до
`0.0.0.0:8080` на MacBook. Усі Python-сервіси всередині VM слухають
`0.0.0.0`, але backend/provider не мають host forwarding.

Перевірка сервісів у Vagrant:

```bash
vagrant ssh ui-service -c "curl -fsS http://127.0.0.1:5000/health"
vagrant ssh backend-service -c "curl -fsS http://127.0.0.1:5001/health"
vagrant ssh provider-service -c "curl -fsS http://127.0.0.1:5002/health"
vagrant ssh database -c "sudo -u postgres pg_isready"
```

## Доступ із локальної мережі

Дізнатися Wi-Fi IP-адресу MacBook:

```bash
ipconfig getifaddr en0
```

Якщо Wi-Fi використовує інший інтерфейс, знайти його можна так:

```bash
networksetup -listallhardwareports
```

На MacBook сайт доступний за обома адресами:

```text
http://localhost:8080
http://<MACBOOK_LAN_IP>:8080
```

На телефоні, підключеному до тієї самої Wi-Fi мережі, відкрийте:

```text
http://192.168.x.x:8080
```

де `192.168.x.x` — результат `ipconfig getifaddr en0`. Якщо у macOS
увімкнено блокування вхідних з'єднань, потрібно дозволити їх для VMware
Fusion/Vagrant. Усередині Ubuntu provisioning автоматично додає порт UI
до UFW, якщо firewall уже активний.

## API

Публічні маршрути UI:

- `GET /health`;
- `GET /api/weather`;
- `GET /api/forecast`;
- `GET /api/history`;
- `DELETE /api/history`.

Внутрішній Backend Service має ті самі `/api/*` маршрути. Внутрішній
Provider Service надає `GET /health`, `GET /weather/current` і
`GET /weather/forecast`; викликати його повинен лише backend.

`GET /api/forecast` завжди читає дані з таблиць
`weather_forecast_state` і `weather_forecast_points`. HTTP-запит до
Provider виконує тільки фонове завдання Backend. Транзакційний advisory
lock PostgreSQL не дозволяє кільком екземплярам Backend одночасно
оновлювати прогноз.

## Час на графіку

Графік показує 24 послідовні погодинні точки останнього успішно
збереженого прогнозу. Точки сортуються за повним timestamp. Якщо
24-годинне вікно перетинає межу дня, вісь показує дату й час, наприклад
`21.07 12:00`. Відображення явно використовує часовий пояс
`Europe/Kyiv`, а кількість підписів адаптується до ширини графіка.
