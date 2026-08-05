# Vagrant deployment guide

## Overview

The Vagrantfile creates four VirtualBox VMs and runs four provisioners on each:

1. `common` installs basic tools and configures hostnames and LAN mappings.
2. `docker` installs Docker Engine and the Compose plugin when missing.
3. `ssh-access` optionally installs a personal public key.
4. `compose` copies the required project files and deploys the role's containers.

| Machine | Fixed memory | CPUs | Default address |
|---|---:|---:|---:|
| `database` | 2048 MB | 2 | `192.168.18.213` |
| `backend` | 640 MB | 1 | `192.168.18.211` |
| `fetcher` | 640 MB | 1 | `192.168.18.212` |
| `frontend` | 640 MB | 1 | `192.168.18.210` |

## Prerequisites

Install and verify:

```powershell
vagrant --version
VBoxManage --version
git --version
```

Use Vagrant 2.4 or newer and VirtualBox 7.x. Keep at least 5 GB of host RAM available; 6 GB is recommended while dependencies and images are first downloaded.

## Configure the root environment

```powershell
Copy-Item .env.example .env
```

Edit `.env` before running Vagrant:

```dotenv
AIRAWARE_NETWORK_PREFIX=192.168.18
AIRAWARE_NETMASK=255.255.255.0
AIRAWARE_BRIDGE_ADAPTER=Intel(R) Wi-Fi 6 AX200 160MHz

AIRAWARE_DB_NAME=airaware
AIRAWARE_DB_USER=airaware_user
AIRAWARE_DB_PASSWORD=replace-with-a-strong-password

AIRAWARE_REDIS_PASSWORD=replace-with-a-different-strong-password

AIRAWARE_RABBITMQ_USER=airaware
AIRAWARE_RABBITMQ_PASSWORD=replace-with-another-strong-password
AIRAWARE_RABBITMQ_VHOST=airaware

AIRAWARE_FLASK_SECRET_KEY=replace-with-at-least-32-random-bytes
```

Generate a Flask key with:

```powershell
python -c "import secrets; print(secrets.token_hex(32))"
```

Explicit host environment variables override matching values in `.env`. The file is ignored by Git.

## Validate bridged networking

List adapters and use the exact name of the active physical adapter:

```powershell
VBoxManage list bridgedifs
```

Confirm `.210` through `.213` are unused and outside the router's dynamic DHCP range or reserved for these VMs:

```powershell
$addresses = 210..213 | ForEach-Object { "192.168.18.$_" }
$addresses | ForEach-Object {
    Test-Connection -ComputerName $_ -Count 1 -Quiet
}
```

Bridged networking intentionally exposes every published container port to the trusted LAN.

## Validate and deploy

```powershell
vagrant validate
vagrant status
```

For clear dependency ordering and easier diagnostics, start machines explicitly:

```powershell
vagrant up database
vagrant up backend
vagrant up fetcher
vagrant up frontend
```

`vagrant up` can start the entire environment in Vagrantfile order.

The Compose provisioner:

- removes the previous copied deployment tree under `/opt/airaware`;
- copies only required source and Compose files;
- generates a root-only `.env` for that role;
- safely quotes dotenv values and percent-encodes URL credentials;
- pulls infrastructure images or builds application images;
- starts containers with `--remove-orphans --wait --wait-timeout 180`;
- prints container status and recent logs if startup fails;
- applies pending SQL migrations after PostgreSQL is healthy.

## Verify

```powershell
vagrant status

curl.exe http://192.168.18.210:5000/health/ready
curl.exe http://192.168.18.211:8001/health/ready
curl.exe http://192.168.18.212:8000/health/ready
```

Inspect each Compose project:

```powershell
vagrant ssh database -c "cd /opt/airaware/deploy/infrastructure && sudo docker compose ps"
vagrant ssh backend -c "cd /opt/airaware/deploy/backend && sudo docker compose ps"
vagrant ssh fetcher -c "cd /opt/airaware/deploy/fetcher && sudo docker compose ps"
vagrant ssh frontend -c "cd /opt/airaware/deploy/frontend && sudo docker compose ps"
```

## Reprovision changes

```powershell
vagrant provision frontend --provision-with compose
vagrant provision backend --provision-with compose
vagrant provision fetcher --provision-with compose
vagrant provision database --provision-with compose
```

Reprovision only the affected role when possible. Infrastructure provisioning retains named volumes and applies unrecorded migrations. It does not rerun applied migration files.

Do not edit files under `/opt/airaware` as the permanent source of truth: the next provision replaces the copied tree and generated `.env`.

## Start and stop

```powershell
vagrant halt
vagrant up
```

Prefer a normal `vagrant halt` and allow the VMs and containers to stop cleanly. Avoid closing VirtualBox processes or powering off the host while infrastructure writes are active.

## Network changes

Change the root `.env`, confirm the new addresses are unused, and recreate the VMs:

```powershell
vagrant destroy -f
vagrant up database
vagrant up backend
vagrant up fetcher
vagrant up frontend
```

Back up PostgreSQL before destroying the database VM.

## Destroying machines

```powershell
vagrant destroy frontend -f
vagrant destroy backend -f
vagrant destroy fetcher -f
```

Destroying `database` removes its virtual disk, including the PostgreSQL, Redis, and RabbitMQ named volumes:

```powershell
vagrant destroy database -f
```

Use the backup procedure in [Operations](operations.md) first.

## Optional personal-key SSH access

Vagrant always retains its managed `vagrant` login. To add a personal key for the `airaware` account, follow [the SSH guide](../ssh/README.md). No helper script is required.

## Security note

This deployment is intended for a trusted home or lab LAN. It does not configure TLS or a host firewall. Do not forward the published ports from the router to the public internet without adding appropriate security controls.
