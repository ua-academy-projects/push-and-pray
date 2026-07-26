# Weather App — Моніторинг погоди у Надвірній

Веб-застосунок для автоматичного збору, збереження та відображення погодних даних (поточний стан, 24-годинний прогноз та історія за 24 години / 7 днів) для міста **Надвірна**.

---

## 🏛 Архітектура

```text
Browser <=======> UI Service <=======> Backend Service <=======> PostgreSQL (weather_history)
                     ||                       ^
                     \/                       || (Consumes)
               Redis (Sessions)          RabbitMQ (Queue: weather_data_queue)
                                             ^
                                             || (Publishes)
                                     Provider Service <=======> Open-Meteo API
```

- **`ui-service`** (порт `5000` внутрішній, `8080` зовнішній):
  - Віддає HTML/CSS/JS інтерфейс.
  - Управляє сесіями користувачів через Redis (`/api/session`).
  - Проксіює всі погодні запити `/api/*` виключно до `backend-service`.

- **`Redis`** (порт `6379`):
  - Зберігає сесійний стан UI (вибраний період історії 24h/7d, пагінація, налаштування).
  - Забезпечує відновлення стану UI після перезавантаження сторінки у браузері.

- **`RabbitMQ`** (порт `5672`, Web UI `15672`):
  - Брокер асинхронних повідомлень між `provider-service` та `backend-service`.
  - Черга `weather_data_queue` транслює поточну погоду, прогнози та історію.

- **`backend-service`** (порт `5001`):
  - Асинхронно споживає (consume) погодні повідомлення з RabbitMQ та зберігає їх у PostgreSQL.
  - Володіє всією бізнес-логікою та доступом до БД PostgreSQL.
  - Надає API: `/api/weather`, `/api/forecast`, `/api/history?hours=24|168`.

- **`provider-service`** (порт `5002`):
  - Спілкується з зовнішнім Open-Meteo API та публікує (publish) оновлення погодних даних у RabbitMQ.
  - Не має прямого доступу до бази даних PostgreSQL.

- **`PostgreSQL`** (порт `5432`):
  - Зберігає всі погодинні точки в єдиній таблиці `weather_hourly_points` із унікальним первинним ключем `(location_key, weather_at)`.


---

## 📁 Структура проєкту

```text
weather-app/
├── backend-service/          # Flask backend, DB міграції, планувальник
│   ├── app.py
│   └── migrations/
│       └── 001_unified_hourly_weather.sql
├── provider-service/         # Flask провайдер для Open-Meteo API
│   └── app.py
├── ui-service/               # Flask UI, шаблони, графіки SVG, стилі
│   ├── app.py
│   ├── static/
│   │   ├── script.js
│   │   └── style.css
│   └── templates/
│       └── index.html
├── providers/                # Скрипти провіжнінгу для Vagrant
│   ├── common.sh
│   ├── database.sh
│   ├── backend.sh
│   ├── provider.sh
│   └── ui.sh
├── docker-compose.yml
├── Vagrantfile
├── .gitignore
└── README.md
```

---

## 🚀 Запуск проєкту

### Варіант 1: Docker Compose

**Вимоги:** Docker та Docker Compose.

```bash
# Запустити всі сервіси у фоновому режимі з перебудовою
docker compose up -d --build

# Перевірити статус контейнерів
docker compose ps

# Переглянути логи
docker compose logs -f
```

**Доступ у браузері:**
[http://localhost:8080](http://localhost:8080)

**Зупинка:**
```bash
docker compose down
```

---

### Варіант 2: Vagrant (VMware Desktop)

**Вимоги:** Vagrant, VMware Desktop/Fusion та Vagrant VMware Utility.

```bash
# Запустити всі 4 віртуальні машини
vagrant up

# Перевірити статус ВМ
vagrant status

# Якщо вносились зміни до коду, оновити сервіси на ВМ:
vagrant provision
```

Vagrant створює 4 віртуальні машини:
| ВМ | IP | Опис |
|---|---:|---|
| `ui-service` | `192.168.56.10` | Веб-інтерфейс (порт `5000` прокинуто на хост `:8080`) |
| `backend-service` | `192.168.56.11` | Backend API та планувальник (порт `5001`) |
| `provider-service` | `192.168.56.12` | Інтеграція з Open-Meteo (порт `5002`) |
| `database` | `192.168.56.13` | PostgreSQL 16 (порт `5432`) |

**Доступ у браузері:**
[http://localhost:8080](http://localhost:8080)

---

## 🔗 API Endpoints

### UI Service (Публічний API)

- `GET /health` — Перевірка стану UI.
- `GET /api/weather` — Поточна погода (температура, вологість, швидкість вітру).
- `GET /api/forecast` — 24-годинний прогноз температури.
- `GET /api/history?hours=24|168` — Історія вимірювань (за 24 години або 7 днів).

### Backend Service (Внутрішній API)

- `GET /health` — Перевірка стану backend та з'єднання з БД.
- `GET /api/weather` — Жива поточна погода з fallback до БД.
- `GET /api/forecast` — 24 точки прогнозу з БД (починаючи з поточної години).
- `GET /api/history?hours=24|168` — Погодинна історія з БД.

### Provider Service (Внутрішній API)

- `GET /health` — Перевірка стану провайдера.
- `GET /weather/current` — Поточний стан з Open-Meteo.
- `GET /weather/forecast` — Прогноз на 24 години з Open-Meteo.
- `GET /weather/history?past_hours=N` — Історія за останні `N` годин з Open-Meteo.

---

## 🗄 База даних (PostgreSQL)

Схема створена в міграції `001_unified_hourly_weather.sql`:

- **`weather_hourly_points`**:
  - `location_key` (`TEXT`) — ключ локації (`nadvirna`).
  - `weather_at` (`TIMESTAMPTZ`) — година вимірювання/прогнозу.
  - `temperature` (`DOUBLE PRECISION`) — температура (°C).
  - `relative_humidity` (`DOUBLE PRECISION`) — відносна вологість (%).
  - `wind_speed` (`DOUBLE PRECISION`) — швидкість вітру (km/h).
  - `data_kind` (`TEXT`) — тип даних: `'current'`, `'forecast'`, або `'historical'`.
  - `PRIMARY KEY (location_key, weather_at)` — запобігає появі дублікатів.

- **`weather_sync_state`**:
  - Зберігає метки часу останньої успішної синхронізації прогнозу та історії.

### Підключення до БД локально (через Vagrant)

```bash
# Пряме підключення з хоста
psql -h 192.168.56.13 -U weather_user -d weather_history
# Пароль: weather_password

# Або через SSH у ВМ database
vagrant ssh database -c "psql -U weather_user -d weather_history"
```

---

## 📊 Інтерфейс користувача

1. **Картка поточного стану:** Показує локацію (Надвірна), поточну температуру, вологість, швидкість вітру та час вимірювання.
2. **Графік прогнозу:** Інтерактивний SVG-графік температури на наступні 24 години.
3. **Графік історії:** Інтерактивний SVG-графік із перемикачем діапазону **«24 години» / «7 днів»**.
4. **Таблиця вимірювань:** Погодинний архів за останні 24 години з детальною інформацією.
