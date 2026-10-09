# App

Runs the three OilScope services in the cluster and publishes the UI over
HTTPS. It expects what the earlier roles create: the namespace and the GHCR
pull Secret (`app_namespace`), the PostgreSQL cluster with its schema
(`database`), Redis (`redis`) and the Let's Encrypt issuers (`cert_manager`).

## What it creates

| Resource | Purpose |
| --- | --- |
| `Secret/oilscope-app` | `OILPRICEAPI_KEY` and `REDIS_PASSWORD`, resolved on a server |
| `Deployment` + `Service` `history` (8001) | Price history API and the pgmq consumer |
| `Deployment` + `Service` `fetcher` (8002) | Scheduled collection; publishes into pgmq |
| `Deployment` + `Service` `ui` (8080) | Web UI and its backend |
| `Middleware/redirect-https` | Traefik answers plain `http://` on the UI's host with a permanent redirect to `https://` |
| `Ingress/ui` | `cluster.ingress.hostname` → `ui`, with a certificate from cert-manager in `Secret/oilscope-tls` |

One replica each: scaling needs the application to share sessions and to
deliver queue messages exactly once, which is a change to the application,
not to the manifests.

## How the services find each other

| Who | Reaches | Through |
| --- | --- | --- |
| UI | History | `http://history:8001` |
| UI | Redis (sessions) | `redis://:<password>@redis:6379/0` |
| History, Fetcher | PostgreSQL | `oilscope-db-rw:5432`, the Service of the primary |
| Browser | UI | Traefik → `Ingress/ui` → `Service/ui` |

The database password is not copied anywhere: each pod reads it from the
`oilscope-db-app` Secret CloudNativePG generated, into `DB_PASSWORD`, and
`DATABASE_URL` refers to it as `$(DB_PASSWORD)`. Kubernetes expands only
variables defined *earlier* in the list, which is why `DB_PASSWORD` comes
first. The password goes into the URL unescaped; that is safe because
CloudNativePG generates letters and digits only
(`password.Generate(64, 10, 0, …)` - no symbols), and the Redis password is
hexadecimal.

`sslmode=require`: CloudNativePG serves TLS and accepts both, so the
connections are encrypted without verifying the server's certificate.

## Choices worth knowing

- **Probes.** Every `/health` checks the service's dependencies - History
  runs `SELECT 1`, the UI calls History and Redis. That is the right
  question for *readiness* (should this pod get traffic?) and the wrong one
  for *liveness* (should it be restarted?): restarting every pod because the
  database is briefly away only makes the outage longer. So readiness asks
  `/health`, liveness only checks that the port answers.
- **Fetcher strategy `Recreate`.** The fetcher runs the collection schedule
  itself; a rolling update would run two of them for a moment.
- **Secret checksum.** Pods do not restart when a Secret they read changes.
  The pod templates carry a checksum of the secret values, so a new value
  changes the template and Kubernetes rolls the pods.
- **Security context.** The images run as `app`, UID 10001. Kubernetes can
  only prove a container is not root from a numeric user, so the pods name
  the UID; privilege escalation is off and every capability dropped - the
  counterpart of `no-new-privileges` in the old Compose files.
- **Placement.** `nodeSelector: cloud=<app.cloud>` keeps the services in the
  cloud of the database and Redis.
- **HTTPS redirect on this Ingress only.** Without it `http://<host>` serves
  the UI unencrypted and browsers flag it as not secure. A global redirect on
  Traefik's `web` entry point would also catch Let's Encrypt's HTTP-01
  check, which arrives over plain HTTP; the redirect is therefore a
  `Middleware` this Ingress names, while the Ingress cert-manager creates for
  the check stays unredirected - its more specific path also wins over `/`.
- **Rollout order.** History, then Fetcher, then the UI, each waiting for its
  rollout: the UI's readiness depends on History.

## Variables

| Variable | From |
| --- | --- |
| `app_image_repository`, `app_image_tag` | `registry.repository`, `registry.image_sha` |
| `app_cloud` | `app.cloud` |
| `app_hostname` | `cluster.ingress.hostname` |
| `app_cluster_issuer` | role default `letsencrypt-prod`; `letsencrypt-staging` while testing |
| `app_oilpriceapi_key`, `app_redis_password` | the `OILPRICEAPI_KEY` and `REDIS_PASSWORD` secrets |
| `app_resources` | role default; requests and limits per service |

## License

GPL-2.0-or-later
