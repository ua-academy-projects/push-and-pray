# Weather Vagrant

Проєкт запускає чотири VM: `db`, `backend`, `fetcher` та `ui`. Для входу по SSH у кожній VM автоматично створюється користувач `weather` з доступом за ключем і правами `sudo` без пароля.

## Перший запуск і SSH у WSL

```bash
cd "/mnt/c/Users/harki/weather-vagrant 2"
vagrant.exe up
vagrant.exe provision
bash ./setup-ssh.sh
```

Після цього нативний Linux OpenSSH підтримує короткі команди:

```bash
ssh db
ssh backend
ssh fetcher
ssh ui
```

Перевірка:

```bash
command -v ssh
ssh backend whoami
```

Очікувані результати: `/usr/bin/ssh` та `weather`.

## Як це працює

1. `provision/common.sh` створює в кожній VM користувача `weather` і записує дозволений публічний ключ у `/home/weather/.ssh/authorized_keys`.
2. `setup-ssh.sh` отримує через `vagrant.exe ssh-config` шлях до приватного ключа кожної VM.
3. Через `vagrant.exe ssh` скрипт читає реальну bridged LAN-адресу VM з `/etc/weatherflow/lan.env`.
4. Приватні ключі копіюються у WSL-каталог `~/.ssh/weather-vagrant/` і отримують безпечні права `600`.
5. Конфіг машин створюється у `~/.ssh/weather-vagrant.conf`, а стандартний `~/.ssh/config` підключає його директивою `Include`.
6. `ssh backend` напряму підключається до LAN-адреси VM на порт `22` як користувач `weather`.

PowerShell і Windows `ssh.exe` для SSH-підключення не використовуються.

Після `vagrant destroy`, нового `vagrant up` або зміни LAN-адрес повторно виконайте:

```bash
bash ./setup-ssh.sh
```
