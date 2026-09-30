# K3s Redis role

Runs on the local Ansible controller and reconciles a pinned, standalone Redis
Helm release in the application namespace. The CloudPirates chart uses the
repository-owned `infrastructure/kubernetes/values/redis.yaml` file and the
official Redis 8.10.2 image pinned by immutable digest.

The values file contains stable, non-secret configuration. The role overlays
the storage request from `k3s.data_services.redis.storage_gb`, the Redis port
from `service_ports.redis`, and the `<name-prefix>-application` Secret name
from the project configuration. The chart maps the Secret's `REDIS_PASSWORD`
key without copying its value into Helm release values.

Redis runs as one StatefulSet replica, uses an internal `ClusterIP` Service,
and requests a `ReadWriteOnce` volume from K3s's `local-path` storage class.
AOF persistence flushes changes every second. Redis can use up to 192 MiB for
data within a 384 MiB container limit and evicts least-recently-used session
keys when it reaches that boundary. Sentinel and metrics are disabled.

This configuration is appropriate for the learning environment and the UI's
TTL-based session store, but it is not a highly available Redis deployment.

This role is retained as historical, non-runnable reference code. It is not
called by the current `deploy_k3s_addons` playbook, which deploys CloudNativePG
and uses PostgreSQL sessions instead. Running it again would first require
restoring its legacy Redis storage and secret fields to a project configuration.
