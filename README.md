# Weather App — Моніторинг погоди у Надвірній

Веб-застосунок для автоматичного збору, збереження та відображення погодних даних (поточний стан, 24-годинний прогноз та історія за 24 години / 7 днів) для міста **Надвірна**.

---

## 🏛 Архітектура

```text
Browser <=======> UI Service Container <=======> Backend Service Container <=======> PostgreSQL Container (weather_history)
(MacBook /             || (192.168.56.10:5000)          ^ (192.168.56.11:5001)           ^ (192.168.56.13:5432)
 LAN IP)               \/                               || (Consumes)                    |
                 Redis Container                 RabbitMQ Container <====================+
               (192.168.56.13:6379)            (192.168.56.13:5672/15672)                ^
                                                                                          || (Publishes)
                                                                                  Provider Service Container
                                                                                    (192.168.56.12:5002) <===> Open-Meteo API
```

- **`ui-service VM`** (`192.168.56.10`, контейнер `ui-service` порт `5000`):
  - Віддає HTML/CSS/JS інтерфейс.
  - Управляє сесіями користувачів через Redis (`192.168.56.13:6379`).
  - Проксіює всі погодні запити `/api/*` виключно до Backend Service (`192.168.56.11:5001`).

- **`backend-service VM`** (`192.168.56.11`, контейнер `backend-service` порт `5001`):
  - Асинхронно споживає (consume) погодні повідомлення з RabbitMQ та зберігає їх у PostgreSQL.
  - Надає API: `/api/weather`, `/api/forecast`, `/api/history?hours=24|168`.

- **`provider-service VM`** (`192.168.56.12`, контейнер `provider-service` порт `5002`):
  - Періодично опитує Open-Meteo API та публікує (publish) оновлення погодних даних у RabbitMQ (`192.168.56.13:5672`).

- **`database VM`** (`192.168.56.13`, Docker Compose):
  - **`PostgreSQL 16`** (`5432`): Зберігає погодинні точки в єдиній таблиці `weather_hourly_points`.
  - **`Redis 7`** (`6379`): Зберігає сесії користувачів UI з увімкненим збереженням `appendonly yes`.
  - **`RabbitMQ 3`** (`5672`, Web UI `15672`): Брокер асинхронних повідомлень.

---

## 📁 Структура проєкту

```text
weather-app/
├── backend-service/
│   ├── app.py
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── requirements.txt
│   └── migrations/
│       └── 001_unified_hourly_weather.sql
├── database-service/
│   └── docker-compose.yml
├── provider-service/
│   ├── app.py
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── requirements.txt
├── ui-service/
│   ├── app.py
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── static/
│   │   ├── script.js
│   │   └── style.css
│   └── templates/
│       └── index.html
├── providers/
│   ├── common.sh
│   ├── database.sh
│   ├── backend.sh
│   ├── provider.sh
│   └── ui.sh
├── tests/
├── Vagrantfile
├── README.md
└── docker-compose.yml
```

---

## 🚀 Розгортання через Vagrant (VMware Fusion / Desktop)

Всередині кожної VM відповідна частина проєкту запускається в ізольованому Docker-контейнері через Docker Compose.

### Запуск та перевірка статусу ВМ

```bash
# Запустити всі 4 ВМ та виконати автоматичний провіжинінг
vagrant up

# Перевірити статус ВМ
vagrant status

# Валідація Vagrantfile
vagrant validate
```

### Перевірка статусу контейнерів на кожній ВМ

```bash
# Database VM (PostgreSQL, Redis, RabbitMQ)
vagrant ssh database -c "docker compose -f /vagrant/database-service/docker-compose.yml ps"

# Provider VM
vagrant ssh provider-service -c "docker compose -f /vagrant/provider-service/docker-compose.yml ps"

# Backend VM
vagrant ssh backend-service -c "docker compose -f /vagrant/backend-service/docker-compose.yml ps"

# UI VM
vagrant ssh ui-service -c "docker compose -f /vagrant/ui-service/docker-compose.yml ps"
```

### Перегляд логів контейнерів

```bash
vagrant ssh database -c "docker compose -f /vagrant/database-service/docker-compose.yml logs --tail=100"
vagrant ssh provider-service -c "docker compose -f /vagrant/provider-service/docker-compose.yml logs --tail=100"
vagrant ssh backend-service -c "docker compose -f /vagrant/backend-service/docker-compose.yml logs --tail=100"
vagrant ssh ui-service -c "docker compose -f /vagrant/ui-service/docker-compose.yml logs --tail=100"
```

---

## 🌐 Мережа та IP-адреси

Усі 4 ВМ мають по два мережевих інтерфейси:
1. **Приватна мережа (`192.168.56.x`)**: Для стабільного міжсервісного зв’язку контейнерів.
2. **Bridged мережа (`public_network`)**: Для отримання IP-адреси від DHCP роутера та доступу з MacBook і пристроїв локальної мережі.

### Команди перегляду всіх IP-адрес ВМ:

```bash
vagrant ssh ui-service -c "ip -4 -br addr"
vagrant ssh backend-service -c "ip -4 -br addr"
vagrant ssh provider-service -c "ip -4 -br addr"
vagrant ssh database -c "ip -4 -br addr"
```

---

## 💻 Доступ до Web UI та RabbitMQ Management

### Доступ до UI:
- **З MacBook (Port Forwarding)**: [http://localhost:8080](http://localhost:8080)
- **З MacBook / Локальної мережі (Bridged IP)**: `http://<BRIDGED_IP_UI>:5000`
- **Приватний IP UI VM**: `http://192.168.56.10:5000`

### Доступ до RabbitMQ Management UI:
- **З MacBook / Локальної мережі (Bridged IP)**: `http://<BRIDGED_IP_DATABASE>:15672`
- **Приватний IP Database VM**: `http://192.168.56.13:15672`

**Авторизація RabbitMQ:**
- **Користувач:** `weather_user`
- **Пароль:** `weather_password`

---

## 🗄 Перевірка бази даних (PostgreSQL у контейнері)

Оскільки PostgreSQL працює у Docker-контейнері, для виконання SQL-запитів використовується команда `docker compose exec`:

```bash
# Підключення до psql всередині PostgreSQL контейнера на database VM
vagrant ssh database -c "cd /vagrant/database-service && docker compose exec database psql -U weather_user -d weather_history"
```

Приклад перевірки записів у консолі psql:
```sql
SELECT weather_at, temperature, data_kind, fetched_at FROM weather_hourly_points ORDER BY weather_at DESC LIMIT 10;
```

---

## 🧪 Тестування

Запуск усіх автоматичних тестів з кореня проєкту:

```bash
python3 -m pytest -q
```
