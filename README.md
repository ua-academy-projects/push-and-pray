# Weather App — Моніторинг погоди у Надвірній

Веб-застосунок для автоматичного збору, збереження та відображення погодних даних (поточний стан, 24-годинний прогноз та історія за 24 години / 7 днів) для міста **Надвірна**.

---

## 🏛 Архітектура

```text
Browser
   │
   ▼
ui-service.local:5000 ───────────────► backend-service.local:5001
   │                                      │
   │                                      ├──► PostgreSQL
   ▼                                      │     database.local:5432
Redis                                     │
database.local:6379                       ◄── RabbitMQ
                                               database.local:5672
                                                    ▲
                                                    │ publish
Open-Meteo API ◄────► provider-service.local:5002 ──┘
```

- **`ui-service VM`** (`ui-service.local`, контейнер `ui-service`, порт `5000`):
  - Віддає HTML/CSS/JS інтерфейс.
  - Управляє сесіями користувачів через Redis на `database.local:6379`.
  - Проксіює погодні запити `/api/*` до Backend Service на `backend-service.local:5001`.

- **`backend-service VM`** (`backend-service.local`, контейнер `backend-service`, порт `5001`):
  - Асинхронно споживає погодні повідомлення з RabbitMQ на `database.local:5672`.
  - Зберігає погодні дані в PostgreSQL на `database.local:5432`.
  - Надає API: `/api/weather`, `/api/forecast`, `/api/history?hours=24|168`.

- **`provider-service VM`** (`provider-service.local`, контейнер `provider-service`, порт `5002`):
  - Періодично опитує Open-Meteo API.
  - Публікує оновлення погодних даних у RabbitMQ на `database.local:5672`.

- **`database VM`** (`database.local`, Docker Compose):
  - **`PostgreSQL 16`** (`5432`): Зберігає погодинні точки в єдиній таблиці `weather_hourly_points`.
  - **`Redis 7`** (`6379`): Зберігає сесії користувачів UI з увімкненим збереженням `appendonly yes`.
  - **`RabbitMQ 3`** (`5672`, Web UI `15672`): Брокер асинхронних повідомлень.

Кожен Compose-проєкт працює на окремій VM. Контейнерні сервіси
слухають `0.0.0.0`, а їхні порти публікуються на bridged-інтерфейсі VM
без прив’язки до конкретної DHCP-адреси.

---

## 📁 Структура проєкту

```text
weather-app/
├── backend-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── migrations/
│   │   └── 001_unified_hourly_weather.sql
│   └── tests/
├── provider-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   └── tests/
├── ui-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── static/
│   │   ├── script.js
│   │   └── style.css
│   ├── templates/
│   │   └── index.html
│   └── tests/
├── infrastructure/
│   ├── compose/
│   │   ├── backend-service.yml
│   │   ├── database-service.yml
│   │   ├── provider-service.yml
│   │   └── ui-service.yml
│   └── vagrant/
│       ├── Vagrantfile
│       └── provisioning/
│           ├── backend.sh
│           ├── common.sh
│           ├── database.sh
│           ├── provider.sh
│           └── ui.sh
├── tests/
├── .env.example
├── requirements-test.txt
├── Vagrantfile              # коренева точка входу
├── README.md
└── LICENSE
```

Код, Dockerfile, залежності та локальні тести кожного Python-сервісу
залишаються в його каталозі. Усі операційні конфігурації згруповані в
`infrastructure/`: кожна VM запускає лише власний Compose-проєкт.
Кореневий `Vagrantfile` завантажує основну конфігурацію з
`infrastructure/vagrant/Vagrantfile`, тому всі команди Vagrant потрібно
виконувати з кореня проєкту.
Після зміни мережевої конфігурації раніше створені VM потрібно видалити
командою `vagrant destroy -f` і створити заново.

Provisioning-скрипти встановлюють Docker, Docker Compose, Avahi та
`libnss-mdns`, відкривають потрібні порти UFW (якщо firewall активний),
визначають актуальні IPv4-адреси залежних VM через їхні `.local`-імена
і передають ці адреси в Compose через змінні середовища. DHCP-адреси у
Compose-файлах не хардкодяться.

---

## 🚀 Розгортання через Vagrant (VMware Fusion / Desktop)

Всередині кожної VM відповідна частина проєкту запускається в ізольованому Docker-контейнері через Docker Compose.

Перед запуском VMware `vmnet0` повинен бути підключений мостом до
фізичного інтерфейсу локальної мережі. Роутер має надавати IPv4-адреси
через DHCP, а всі чотири VM мають бути в одній LAN.

### Запуск та перевірка статусу ВМ

```bash
# Запустити всі 4 ВМ та виконати автоматичний провіжинінг
vagrant up

# Перевірити статус ВМ
vagrant status

# Валідація Vagrantfile
vagrant validate
```

VM оголошені в порядку залежностей: `database`, `provider-service`,
`backend-service`, `ui-service`. Provisioning запускається під час
кожного `vagrant up`; залежні VM очікують, доки потрібні `.local`-імена
почнуть резолвитися.

За потреби VM можна запускати окремо в тому самому порядку:

```bash
vagrant up database
vagrant up provider-service
vagrant up backend-service
vagrant up ui-service
```

### Перевірка статусу контейнерів на кожній ВМ

```bash
# Database VM (PostgreSQL, Redis, RabbitMQ)
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml ps"

# Provider VM
vagrant ssh provider-service -c "docker compose -f /vagrant/infrastructure/compose/provider-service.yml ps"

# Backend VM
vagrant ssh backend-service -c "docker compose -f /vagrant/infrastructure/compose/backend-service.yml ps"

# UI VM
vagrant ssh ui-service -c "docker compose -f /vagrant/infrastructure/compose/ui-service.yml ps"
```

### Перегляд логів контейнерів

```bash
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml logs --tail=100"
vagrant ssh provider-service -c "docker compose -f /vagrant/infrastructure/compose/provider-service.yml logs --tail=100"
vagrant ssh backend-service -c "docker compose -f /vagrant/infrastructure/compose/backend-service.yml logs --tail=100"
vagrant ssh ui-service -c "docker compose -f /vagrant/infrastructure/compose/ui-service.yml logs --tail=100"
```

---

## 🌐 Мережа, DHCP та mDNS

Кожна VM має один VMware-адаптер `ethernet0`:

- режим підключення — `bridged` через `vmnet0`;
- IPv4-адреса призначається DHCP-сервером локального роутера;
- NAT, private/host-only network і forwarded ports не використовуються;
- Vagrant SSH та provisioning працюють через bridged DHCP-адресу;
- додаткові VMware-адаптери вимкнені.

Стабільні мережеві імена публікуються через Avahi/mDNS:

| VM       | mDNS hostname            | Контейнери та опубліковані порти                                        |
| -------- | ------------------------ | ----------------------------------------------------------------------- |
| UI       | `ui-service.local`       | UI `5000`                                                               |
| Backend  | `backend-service.local`  | Backend API `5001`                                                      |
| Provider | `provider-service.local` | Provider API `5002`                                                     |
| Database | `database.local`         | PostgreSQL `5432`, Redis `6379`, RabbitMQ `5672`, Management UI `15672` |

Provisioning резолвить ці імена в актуальні LAN IPv4-адреси, ігноруючи
loopback та link-local адреси, після чого передає їх у відповідні
Compose-проєкти як `BACKEND_IP`, `PROVIDER_IP` і `DATABASE_IP`.

### Перегляд LAN IPv4-адрес VM

Команди нижче показують глобальні IPv4-адреси без `docker0` і Docker
bridge-інтерфейсів:

```bash
vagrant ssh ui-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh backend-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh provider-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh database -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
```

---

## 💻 Доступ до Web UI та RabbitMQ Management

### Доступ до UI:

- **Через mDNS:** [http://ui-service.local:5000](http://ui-service.local:5000)
- **Через поточну DHCP-адресу:** `http://<UI_DHCP_IP>:5000`

### Доступ до RabbitMQ Management UI:

- **Через mDNS:** [http://database.local:15672](http://database.local:15672)
- **Через поточну DHCP-адресу:** `http://<DATABASE_DHCP_IP>:15672`

Доступ через `localhost:8080` відсутній, оскільки port forwarding більше
не налаштований.

**Авторизація RabbitMQ:**

- **Користувач:** `weather_user`
- **Пароль:** `weather_password`

---

## 🗄 Перевірка бази даних (PostgreSQL у контейнері)

Оскільки PostgreSQL працює у Docker-контейнері, для виконання SQL-запитів використовується команда `docker compose exec`:

```bash
# Підключення до psql всередині PostgreSQL контейнера на database VM
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml exec database psql -U weather_user -d weather_history"
```

Compose-проєкт бази даних і надалі має ім’я `database-service`, а PostgreSQL
використовує наявний Docker volume `database-service_postgres_data`.
Переміщення YAML-файлу не створює новий volume і не видаляє наявні дані.

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
