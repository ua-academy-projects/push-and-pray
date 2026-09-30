# K3s standalone PostgreSQL role

Runs on the local Ansible controller and reconciles the earlier pinned,
single-instance PostgreSQL Helm release in the application namespace. It is
retained as historical, non-runnable reference code and is not called by the
current `deploy_k3s_addons` playbook, which deploys CloudNativePG instead. Its
legacy configuration fields and credentials are absent from the active schema,
and it must not be run alongside the CloudNativePG release.

The role uses `infrastructure/kubernetes/values/postgresql.yaml`, overlays the
configured storage size and service port, and reads `POSTGRES_PASSWORD` from
the existing application Secret. It provides no PostgreSQL replication or
automatic failover.
