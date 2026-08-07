# Архітектура без Docker Swarm

## Рівні розгортання

```text
Linux host
  → Vagrant
    → 6 Ubuntu VM з bridged IP
      → Docker Compose на прикладних VM
        → контейнери програми
      → systemd timer і Bash collector на Logging VM
```

Compose-мережі не розтягуються між VM. Міжмашинний зв’язок проходить через
LAN-адреси `192.168.10.210-215` і published ports.

## Контейнери

| VM | Compose-файл | Контейнери |
|---|---|---|
| Database | `compose/database/compose.yaml` | PostgreSQL |
| Redis | `compose/redis/compose.yaml` | Redis |
| Fetcher | `compose/fetcher/compose.yaml` | Fetcher |
| Backend | `compose/backend/compose.yaml` | Backend, RabbitMQ |
| UI | `compose/ui/compose.yaml` | UI, Caddy |
| Logging | немає Compose | Bash collector, systemd timer, log files |

`Vagrantfile` зберігає один `config.vm.define` всередині `machines.each`.
Кожна VM отримує роль, а `provision/node.sh` вибирає відповідний Compose-файл.

## SSH-доступ

`provision/node.sh` створює користувача `wildlife` на кожній VM, копіює йому
актуальний публічний ключ Vagrant у `~/.ssh/authorized_keys` та додає до груп
`sudo` і `docker`. Пароль для SSH не використовується.

Після запуску всіх VM `setup-ssh-config.sh` читає приватні ключі командою
`vagrant ssh-config` і додає керований блок у локальний `~/.ssh/config`:

```text
ssh backend → wildlife@192.168.10.211:22
ssh database → wildlife@192.168.10.210:22
ssh logging → wildlife@192.168.10.215:22
```

Таким чином, SSH проходить через bridged LAN IP відповідної VM, а не через
`localhost` і переадресований Vagrant-порт.

## Пошук користувача

1. Browser встановлює HTTPS-з'єднання з Caddy на `192.168.10.213:443`.
2. Caddy завершує TLS і проксіює HTTP-запит до контейнера UI на порту `5000`.
3. UI викликає Backend на `192.168.10.211:8000`.
4. Backend викликає Fetcher на `192.168.10.212:8002`.
5. Fetcher перевіряє назву й викликає офіційний GBIF API.
6. Fetcher повертає Backend готовий JSON.
7. Backend записує початковий стан або реальну зміну в PostgreSQL
   `192.168.10.210:5432`.
8. Backend повертає дані UI.
9. UI зберігає тему та останній екран у Redis `192.168.10.214:6379`.

Оновлення сторінки виконує тільки GET. Збережений `303 Redirect` не дозволяє
F5 повторити запит GBIF.

## Локальний TLS

Caddy на UI VM є локальним центром сертифікації та HTTPS reverse proxy.
Сертифікат UI містить IP SAN із `UI_HOST`. HTTP-порт `80` використовується
тільки для перенаправлення на HTTPS, порт `443` приймає браузерні запити, а
Flask-порт `5000` доступний лише в Docker-мережі `ui_private`.

Ключі CA і серверний приватний ключ зберігаються у Docker volume
`wildlife_caddy_data`. Provisioning експортує тільки публічний сертифікат CA
у `tls/wildlife-local-root-ca.crt`. Його потрібно встановити у сховище довіри
клієнтського пристрою. Видалення UI VM через `vagrant destroy ui` видаляє
volume, тому новостворений CA потрібно буде встановити повторно.

## Централізоване логування

```text
Database VM ─┐
Redis VM ────┤
Fetcher VM ──┤
Backend VM ──┼─ journalctl ◄── SSH pull кожні 2 хвилини
UI VM ───────┤
              └────────────────→ Logging VM → /var/log/wildlife/*.log
```

Docker logging driver `journald` спрямовує stdout/stderr контейнерів у journal
відповідної VM. Logging VM зберігає окремий journal cursor для кожної машини,
підключається до неї окремим SSH-ключем і забирає тільки записи після цього
cursor. Перший успішний запуск забирає журнал поточного boot кожної VM.
SSH виконується від окремого користувача `wildlife-log-reader`, який має право
читати journal, але не має `sudo` або доступу до Docker socket.

Результати зберігаються у `/var/log/wildlife/<role>.log`. Локальний journald
має ліміт 500 MB і retention сім днів; центральні файли щодня обробляє
`logrotate` з 30 ротаціями та стисненням. Якщо одна VM недоступна, її cursor
не змінюється, а помилка записується у `collector-errors.log`.

## Плановий збір

1. `wildlife-fetcher-refresh.timer` спрацьовує 1 січня або 1 липня.
2. Timer викликає локальний Fetcher endpoint.
3. Fetcher публікує job у RabbitMQ `192.168.10.211:5672`.
4. Backend consumer отримує job.
5. Backend читає список відомих видів із PostgreSQL.
6. Backend надсилає список Fetcher.
7. Fetcher отримує актуальні counts із GBIF.
8. Backend записує тільки значення, які справді змінилися.

Якщо RabbitMQ недоступний, Fetcher використовує exponential backoff. Якщо
оновлення не виконалось, Backend повторно ставить job у чергу; після вичерпання
спроб повідомлення потрапляє у `wildlife.refresh.failed`.

## Ізоляція Backend

На Backend VM файл `compose/backend/compose.yaml` використовує контейнерну
підмережу `172.29.0.0/24`.
`provision/node.sh` створює правило в `DOCKER-USER`:

```text
Backend containers → 172.29.0.0/24    ALLOW (RabbitMQ на цій самій VM)
Backend containers → 192.168.10.0/24  ALLOW (Database і Fetcher)
Backend containers → інші мережі      REJECT
```

Отже Backend може викликати Database та Fetcher у LAN, але прямий виклик
глобального GBIF API заблокований. Fetcher VM зберігає зовнішній доступ.

## Внутрішня авторизація

Backend і Fetcher передають заголовок:

```text
X-Internal-Service-Token
```

Значення береться з `INTERNAL_SERVICE_TOKEN` у `deploy.env`. Fetcher відхиляє
внутрішні endpoints без правильного токена.
