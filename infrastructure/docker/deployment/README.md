# Cloud deployment Compose

These Compose files are the deployment-only configuration for the four GCP
VMs. They pull prebuilt images and contain no application build instructions.
The existing files in the parent directory remain the local/Vagrant setup.

## Runtime environment

Cloud-init will create a root-owned environment file at:

```text
/opt/oilscope/runtime/.env
```

Use mode `0600`. Secret values will be fetched from Secret Manager at runtime;
they must not be committed or embedded in Compose, Terraform, metadata, or
cloud-init.

The file is regenerated from Secret Manager whenever
`oilscope-deployment.service` starts or reloads. Cloud-init metadata contains
only secret IDs and non-sensitive configuration, never secret values.

Required variables by VM:

| VM | Required variables |
|---|---|
| Infra | `DB_PASSWORD`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD` |
| History | `GHCR_OWNER`, `HISTORY_IMAGE_TAG`, `DB_PASSWORD`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD` |
| Fetcher | `GHCR_OWNER`, `FETCHER_IMAGE_TAG`, `DB_PASSWORD`, `OILPRICEAPI_KEY` |
| UI | `GHCR_OWNER`, `UI_IMAGE_TAG`, `DB_PASSWORD`, `APP_DOMAIN`, `ACME_EMAIL` |

`FETCHER_IMAGE_TAG`, `HISTORY_IMAGE_TAG`, and `UI_IMAGE_TAG` must be immutable
full commit SHA tags published by GitHub Actions. Do not use `latest`, `main`,
`develop`, or `integration`.

Because application packages are private, cloud-init must authenticate Docker
to `ghcr.io` before `docker compose pull`, using the GHCR username and read-only
token fetched from Secret Manager. Those login credentials are not application
container environment variables and are not referenced by the Compose files.
Authentication uses a temporary Docker configuration under `/run`; the token
is provided with `--password-stdin`, is not printed, and the temporary Docker
configuration is removed after the pull.

## Fixed internal addresses

| VM | Address |
|---|---|
| Fetcher | `10.10.0.10` |
| History | `10.10.0.11` |
| Infra | `10.10.0.12` |
| UI | `10.10.0.14` |

PostgreSQL listens on Infra TCP `5432`, RabbitMQ listens on Infra TCP `5672`,
and History listens on TCP `8001`. GCP firewall rules restrict those ports to
the required source VMs. RabbitMQ management TCP `15672` is not published.

On UI, only Traefik publishes host ports `80` and `443`. The UI service exposes
`8080` only on the `oilscope-proxy` Docker network. Traefik redirects HTTP to
HTTPS and obtains a Let's Encrypt certificate for `APP_DOMAIN` using the HTTP
challenge. DNS must already point `APP_DOMAIN` at the UI VM's reserved external
address before certificate issuance.

## Persistent directories

Cloud-init must create and set container-compatible ownership on these paths
before startup:

```text
/opt/oilscope/data/postgres
/opt/oilscope/data/rabbitmq
/opt/oilscope/data/traefik
```

The PostgreSQL and RabbitMQ paths will reside on the Infra VM's mounted GCP
persistent disk. Traefik stores its ACME state in
`/opt/oilscope/data/traefik/acme.json`; cloud-init must create that file with
mode `0600` before Traefik starts.

On Infra, cloud-init detects the attached disk by its stable GCP device name,
formats it as ext4 only when no filesystem exists, persists its UUID in
`/etc/fstab`, and mounts it at `/opt/oilscope/data`. It never blindly reformats
an existing filesystem.

## Pull and start

Run the matching file on each VM:

```bash
docker compose \
  --env-file /opt/oilscope/runtime/.env \
  --file /opt/oilscope/deployment/compose.ROLE.yaml \
  pull

docker compose \
  --env-file /opt/oilscope/runtime/.env \
  --file /opt/oilscope/deployment/compose.ROLE.yaml \
  up --detach --no-build --remove-orphans
```

Replace `ROLE` with `infra`, `history`, `fetcher`, or `ui`. No application
image is built on a target VM.

Cloud-init and the installed systemd unit handle directory creation,
persistent-disk mounting, GHCR login, secret retrieval, retries, and automatic
startup after VM reboot. Every VM also receives a persistent 1 GiB swap file.

The systemd unit is `oilscope-deployment.service`. Useful commands are:

```bash
cloud-init status --long
sudo systemctl status oilscope-deployment.service
sudo journalctl -u oilscope-deployment.service
sudo systemctl restart oilscope-deployment.service
sudo docker compose \
  --env-file /opt/oilscope/runtime/.env \
  --file /opt/oilscope/deployment/compose.ROLE.yaml \
  ps
```

Database migration execution is not included. The repository currently has
SQL files and a Vagrant-specific migration loop but no deployment migration
artifact or cloud-supported command. An approved migration delivery and
execution step is required before the application is expected to become
healthy.
