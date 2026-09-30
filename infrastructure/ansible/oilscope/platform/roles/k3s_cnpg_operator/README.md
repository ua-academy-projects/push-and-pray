# K3s CloudNativePG operator role

Runs on the local Ansible controller and installs the official, pinned
CloudNativePG operator Helm chart in the `cnpg-system` namespace. The operator
watches the whole Kubernetes cluster so it can reconcile PostgreSQL resources
in the application namespace.

The chart installs its CRDs and webhook, uses one operator replica, and does not
create Prometheus or Grafana resources. PostgreSQL instances are managed by the
separate `k3s_postgresql` role.
