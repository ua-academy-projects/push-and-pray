# K3s PostgreSQL role

Runs on the local Ansible controller and reconciles a pinned, standalone
PostgreSQL Helm release in the application namespace. The chart uses the
repository-owned `infrastructure/kubernetes/values/postgresql.yaml` file and
an immutable PostgreSQL 18 image digest.

The values file contains stable, non-secret configuration. The role overlays
the storage request from `k3s.data_services.postgresql.storage_gb`, the
PostgreSQL port from `service_ports.postgresql`, and the
`<name-prefix>-application` Secret name from the project configuration. The
chart maps the Secret's `POSTGRES_PASSWORD` key to the `oil_tracker` database
user without copying the password into Helm release values.

PostgreSQL runs as one StatefulSet replica, uses an internal `ClusterIP`
Service, and requests a `ReadWriteOnce` volume from K3s's `local-path` storage
class. This is appropriate for the learning environment but does not provide a
highly available database or storage that can move transparently between
nodes.

Run the role as part of the controller-side add-on playbook from the repository
root while the SSH tunnel to the private K3s API is active. Helm and the Helm
Diff plugin must be installed on the controller; Helm Diff prevents unchanged
OCI releases from creating unnecessary revisions.

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```
