# Дика природа України

Python-програма працює у Docker-контейнерах на шести Ubuntu VM, які створює
Vagrant. Docker Swarm не використовується: кожна VM має власний
`compose.yaml`, а сервіси між VM звертаються до bridged LAN IP.

## Розміщення

| VM | IP | Docker Compose запускає |
|---|---:|---|
| Database | `192.168.10.210` | PostgreSQL |
| Backend | `192.168.10.211` | Backend + RabbitMQ |
| Fetcher | `192.168.10.212` | Fetcher |
| UI | `192.168.10.213` | UI + Caddy HTTPS proxy/local CA |
| Redis | `192.168.10.214` | Redis |
| Logging | `192.168.10.215` | Bash collector + journal files |

RabbitMQ залишається окремим контейнером на Backend VM. Docker-контейнери
пишуть stdout/stderr у systemd journal відповідної VM, а Logging VM раз на дві
хвилини забирає нові записи через SSH.

## Два робочі потоки

Явний пошук користувача:

```text
Browser → HTTPS/Caddy → UI → Backend → Fetcher → GBIF
                                   ← готові GBIF-дані
                                   → PostgreSQL
                      ← результат
```

Тільки Fetcher містить GBIF-клієнт і має доступ до глобальної мережі.
Backend-контейнер може звертатися лише до домашньої LAN і не може самостійно
викликати `api.gbif.org`.

Планове оновлення:

```text
systemd timer → Fetcher → RabbitMQ → Backend
                                      ↓
                                   Fetcher → GBIF
                                      ↓
                                  PostgreSQL
```

Планове оновлення виконується 1 січня і 1 липня о 03:00. Retry Fetcher,
Backend retry і failed queue збережені.

## Запуск через Vagrant

Потрібні Vagrant і VirtualBox. Docker Desktop для VM-режиму не потрібний.

```bash
cp deploy.env.example deploy.env
```

Перевір IP, назву bridged-адаптера і заміни тестові паролі та токени у
`deploy.env`. Потім:

```bash
./compose-up.sh
```

Скрипт послідовно створює VM та запускає їхні Compose-проєкти:

1. Logging: Bash-колектор і каталог журналів;
2. Database;
3. Redis;
4. Fetcher;
5. Backend + RabbitMQ;
6. UI.

Після запуску `setup-ssh-config.sh` створює на локальному хості SSH-аліаси для
всіх VM. На кожній VM provisioning створює користувача `wildlife`, додає йому
Vagrant SSH-ключ і право виконувати адміністративні команди через `sudo`.

Сайт:

```text
https://192.168.10.213
```

Централізовані логи переглядаються через SSH:

```bash
ssh logging
sudo ls -lh /var/log/wildlife
sudo tail -f /var/log/wildlife/backend.log
```

Під час першого provisioning UI VM Caddy створює локальний CA і серверний
сертифікат із IP SAN для `192.168.10.213`. Приватний ключ CA залишається у
Docker volume `wildlife_caddy_data`, а публічний Root CA експортується у:

```text
tls/wildlife-local-root-ca.crt
```

Щоб браузер довіряв цьому CA, після `compose-up.sh` виконай на Linux-машині,
з якої відкривається UI, з кореня проєкту:

```bash
bash ./install-local-ca.sh
```

Скрипт через `sudo` встановлює лише публічний Root CA у системне сховище
довіри Linux. Підтримуються Debian/Ubuntu та RHEL/Fedora-сумісні системи.
Порт Flask `5000` у LAN більше не публікується: HTTP на
порті `80` перенаправляється на HTTPS, а Caddy проксіює запити до UI через
приватну Docker-мережу.

Перевірки:

```text
http://192.168.10.212:8002/health
http://192.168.10.211:8000/health
http://192.168.10.211:15672
```

Після звичайного вимкнення достатньо:

```bash
vagrant halt
vagrant up
```

Контейнери мають `restart: unless-stopped`, тому Docker запускає їх разом із
VM. Після зміни коду, Dockerfile, Compose або provision:

```bash
./compose-up.sh
```

## Окремі Compose-файли

```text
compose/database/compose.yaml
compose/redis/compose.yaml
compose/fetcher/compose.yaml
compose/backend/compose.yaml
compose/ui/compose.yaml
```

Загального Compose-файлу для всіх сервісів немає. `provision/node.sh` отримує
роль VM і запускає відповідний Compose-файл. Logging VM не запускає
контейнерів: її systemd timer виконує Bash-колектор.

Перевірити контейнери:

```bash
vagrant ssh database -c "sudo docker ps"
vagrant ssh redis -c "sudo docker ps"
vagrant ssh fetcher -c "sudo docker ps"
vagrant ssh backend -c "sudo docker ps"
vagrant ssh ui -c "sudo docker ps"
vagrant ssh logging -c \
  "systemctl status wildlife-log-collector.timer --no-pager"
```

## Короткі SSH-підключення

Після `./compose-up.sh` можна підключатися без IP, імені користувача та ручного
вказування ключа:

```bash
ssh database
ssh redis
ssh fetcher
ssh backend
ssh ui
ssh logging
```

Також доступні повні аліаси, наприклад:

```bash
ssh wildlife-backend
```

Скрипт `setup-ssh-config.sh` отримує шлях до приватного ключа через
`vagrant ssh-config` і керує лише блоком `ANIMAL-POPULATION-UKRAINE VMS` у
локальному файлі `~/.ssh/config`. Інші SSH-налаштування користувача він не
видаляє. Повторно згенерувати аліаси можна командою:

```bash
./setup-ssh-config.sh
```

У `deploy.env` ім’я Linux-користувача задається змінною:

```text
VM_ADMIN_USER=wildlife
```

## Централізовані логи

Усі Compose-сервіси використовують Docker logging driver `journald`, тому
stdout/stderr застосунків, PostgreSQL, Redis, RabbitMQ і Caddy потрапляють у
systemd journal своєї VM. Caddy додатково пише access log у JSON на stdout.

На Logging VM systemd timer кожні дві хвилини запускає
`/usr/local/sbin/wildlife-collect-logs`. Скрипт через окремий SSH-ключ виконує
`journalctl` на кожній VM і записує результат у:

```text
/var/log/wildlife/database.log
/var/log/wildlife/redis.log
/var/log/wildlife/fetcher.log
/var/log/wildlife/backend.log
/var/log/wildlife/ui.log
/var/log/wildlife/logging.log
/var/log/wildlife/collector-errors.log
```

Для кожної VM зберігається journal cursor у
`/var/lib/wildlife-log-collector`. Тому успішно отримані записи не дублюються,
а після короткої недоступності VM колектор продовжує з останньої збереженої
позиції. Перший успішний запуск забирає журнал поточного boot кожної VM.

Приватний SSH-ключ колектора залишається на Logging VM. У спільний каталог
проєкту експортується тільки його публічна частина. Provisioning створює на
інших VM окремого користувача `wildlife-log-reader`, додає його лише до групи
`systemd-journal` і забороняє цьому ключу port/agent/X11 forwarding та PTY.
Колектор не використовує адміністративного користувача `wildlife` або `sudo`.

Локальний journald обмежений 500 MB і сімома днями. Центральні файли щодня
ротуються через `logrotate`, стискаються та зберігаються 30 ротацій.

Корисні команди:

```bash
vagrant ssh logging -c \
  "systemctl list-timers wildlife-log-collector.timer"
vagrant ssh logging -c \
  "sudo systemctl start wildlife-log-collector.service"
vagrant ssh logging -c \
  "sudo tail -n 100 /var/log/wildlife/collector-errors.log"
vagrant ssh logging -c \
  "sudo tail -f /var/log/wildlife/backend.log"
```

## Плановий Fetcher

Стан таймера:

```bash
vagrant ssh fetcher -c \
  "systemctl list-timers wildlife-fetcher-refresh.timer"
```

Ручний запуск:

```bash
vagrant ssh fetcher -c \
  "sudo systemctl start wildlife-fetcher-refresh.service"
```

Лог:

```bash
vagrant ssh fetcher -c \
  "sudo journalctl -u wildlife-fetcher-refresh.service -n 100 --no-pager"
```

Сервіс викликає Fetcher endpoint на тій самій VM. Fetcher із retry публікує
persistent-повідомлення RabbitMQ. Backend consumer отримує повідомлення,
просить Fetcher забрати актуальні дані GBIF і записує тільки справжні зміни.

## PostgreSQL

```bash
vagrant ssh database
cd /vagrant
sudo docker compose \
  --env-file deploy.env \
  -f compose/database/compose.yaml \
  exec database psql -U wildlife_user -d wildlife
```

```sql
\dt
SELECT * FROM species_observation_state;
SELECT * FROM observation_changes ORDER BY changed_at DESC;
\q
```

PostgreSQL, Redis і RabbitMQ використовують Docker volumes.
`vagrant halt` їх не видаляє. `vagrant destroy` видаляє VM разом із її
локальними volumes. `vagrant destroy logging` також видалить файли журналів,
journal cursors і приватний SSH-ключ колектора на Logging VM.

## Важливі файли

- `fetcher_service/gbif.py` — єдиний клієнт зовнішнього GBIF API;
- `fetcher_service/animals.py` — українські назви та валідація;
- `fetcher_service/main.py` — HTTP Fetcher і публікація планового job;
- `api_service/fetcher_client.py` — Backend-клієнт до Fetcher;
- `api_service/main.py` — API, History і RabbitMQ consumer;
- `api_service/repository.py` — PostgreSQL та реальні зміни;
- `shared/rabbitmq.py` — спільний RabbitMQ-код;
- `compose/ui/Caddyfile` — завершення TLS і проксіювання до Flask UI;
- `logging/collect-logs.sh` — збір journal кожної VM у центральні файли;
- `install-local-ca.sh` — довіра до публічного локального Root CA у Linux;
- `tls/README.md` — розташування та життєвий цикл локального CA;
- `provision/node.sh` — спільний Docker Compose provision усіх VM;
- `compose-up.sh` — послідовний запуск усього проєкту;
- `setup-ssh-config.sh` — локальні SSH-аліаси для всіх VM;
- `compose/*/compose.yaml` — окремий Compose-проєкт кожної VM.

## Значення даних

Програма показує кількість зареєстрованих GBIF occurrence-записів в Україні,
а не точну чисельність живих тварин.
