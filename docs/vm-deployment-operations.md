# VM deployment operations

This describes operating a workload VM's automated deployment — the
`oilscope-deploy.service` systemd unit that cloud-init installs, and the
`run.sh` script it runs. This is the automated path; for manually running
`compose.deployment.yaml` by hand instead, see
[the supported Compose deployment guide](supported-compose-deployment.md).

Every workload VM runs exactly one role (`database`, `history`, `fetcher`, or
`ui`), and `oilscope-deploy.service` starts exactly that role's service(s)
from `/opt/oilscope/deploy/compose.deployment.yaml`. All commands below run
on the VM itself, over SSH through the bastion.

There are two separate things to look at, not one: `oilscope-deploy.service`
itself (the deploy *attempt* — did `run.sh` finish successfully) and the
Docker container(s) it started (the *application* — is History/Fetcher/UI/
Postgres actually running right now). Checking only one gives an incomplete
picture.

## Checking deployment status

Whether the last deploy attempt succeeded:

```sh
systemctl status oilscope-deploy.service
```

`active (exited)` with no error means `run.sh` ran to completion, including
its own health check, on its last invocation. `failed` means it didn't —
check the logs below for why. Since this is a `Type=oneshot` unit, it has no
persistent "running" state between invocations; it only ever reports the
result of its most recent run.

Whether the actual container(s) for this VM's role are up:

```sh
docker compose -f /opt/oilscope/deploy/compose.deployment.yaml ps
```

## Reading deployment logs

**`run.sh`'s own output** — what the deploy script itself printed (which
step it was on, any error message) — goes through the systemd journal, not
Docker:

```sh
journalctl -u oilscope-deploy.service          # full history
journalctl -u oilscope-deploy.service -f       # follow live
journalctl -u oilscope-deploy.service --since "1 hour ago"
```

**The application's own logs** — what History/Fetcher/UI/Postgres printed
while running — go through Docker's own logging, since
`compose.deployment.yaml` does not configure a `journald` logging driver.
Do not look for these in `journalctl`:

```sh
docker compose -f /opt/oilscope/deploy/compose.deployment.yaml logs <service>
docker compose -f /opt/oilscope/deploy/compose.deployment.yaml logs -f <service>
```

Replace `<service>` with whichever this VM's role actually runs
(`postgres`/`migrate` on the `database` VM, otherwise the role name itself —
`history`, `fetcher`, or `ui`).

## Restarting a role

`run.sh` is idempotent and safe to re-run — see the idempotency notes for
why. To redeploy (for example, after a new `APP_IMAGE_TAG` is published),
re-run the whole deploy script through systemd rather than calling
`docker compose` directly:

```sh
sudo systemctl restart oilscope-deploy.service
```

This re-authenticates to GHCR, re-pulls images, and re-applies the correct
`up`/`run` sequence for this VM's role — it will only actually recreate a
container if something about it changed (a newer image, for instance);
otherwise it's a fast no-op.

## Stopping a role

There is no running process behind `oilscope-deploy.service` to stop — it
already exited after its last successful run. What you actually want to stop
is the application container(s) it started:

```sh
docker compose -f /opt/oilscope/deploy/compose.deployment.yaml stop <service>
```

This stops the container(s) without removing them, so a later
`systemctl restart oilscope-deploy.service` (or a VM reboot) brings them
back. To also disable automatic restart on the next boot, additionally stop
and disable the unit itself:

```sh
sudo systemctl disable --now oilscope-deploy.service
```
