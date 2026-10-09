# Redis

Runs Redis for the UI's sessions (`SESSION_BACKEND=redis`), from the
[groundhog2k/redis](https://github.com/groundhog2k/helm-charts) chart.

## Why this chart

Bitnami, the usual Redis chart, stopped publishing free images in August
2025. groundhog2k's chart runs the official, unmodified `redis` image from
Docker Hub. Valkey's official chart would be the other choice - a Redis fork
the UI's client speaks to unchanged - but the requirement is Redis.

## What it creates

| Resource | Purpose |
| --- | --- |
| `Secret/redis-config` | `auth.conf` with `requirepass`; the chart appends it to `redis.conf` |
| `Secret/redis-env` | `REDISCLI_AUTH`, so the chart's probes authenticate |
| Helm release `redis` | Deployment, a PVC of `redis.storage_gb`, and `Service/redis` on 6379 |

The UI reaches it at `redis://:<password>@redis.<namespace>:6379/0`.

### Why two Secrets and REDISCLI_AUTH

The chart appends *every* file of `extraSecretRedisConfigs` to `redis.conf`
and turns *every* key of `extraRedisEnvSecrets` into an environment
variable, so the config line and the bare password cannot share a Secret.

The chart's liveness and readiness probes run a bare `redis-cli ping`.
Against a password, Redis answers `NOAUTH Authentication required` - and
`redis-cli` still exits 0, so the probes would pass while checking nothing
(tested against `redis:8.10.2`). With `REDISCLI_AUTH` set, `redis-cli`
authenticates and the probe sees a real `PONG`.

## Values

`templates/values.yaml.j2` holds only what differs from the chart's defaults:
the two Secrets, a persistent volume (without a size the chart keeps the data
in an `emptyDir`, lost with the pod), requests and limits, and the node
selector. The template is rendered and passed to `kubernetes.core.helm` as
`values`, so the sizes come from the configuration.

## Variables

| Variable | From |
| --- | --- |
| `redis_version` | `cluster.charts.redis.version` |
| `redis_password` | the `REDIS_PASSWORD` secret, resolved on a server |
| `redis_cloud` | `redis.cloud` - the cloud the UI runs in |
| `redis_storage_gb` | `redis.storage_gb` |
| `redis_resources` | role default; requests and limits |

Changing the password updates both Secrets, but a running pod keeps the old
one until it restarts:
`kubectl rollout restart deployment/redis -n <namespace>`.

## License

GPL-2.0-or-later
