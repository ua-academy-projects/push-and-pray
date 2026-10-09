# cnpg

Installs the official CloudNativePG operator through the K3s Helm controller
and creates a small PostgreSQL cluster for OilScope.

The role:

- installs a pinned CloudNativePG Helm chart in `cnpg-system`;
- creates the application namespace;
- passes the application database password to Kubernetes without writing it
  to a manifest on disk;
- creates one primary and `cnpg_instances - 1` standby instances;
- provisions one persistent volume claim per PostgreSQL instance;
- waits for the cluster and its writable Service to become ready.

The role must run on the K3s bootstrap server after the complete K3s cluster is
ready. It does not run database migrations and does not deploy the OilScope
application.

## Required variable

```yaml
cnpg_postgres_password: "{{ resolve_secrets_result.POSTGRES_PASSWORD }}"
```

## Important variables

```yaml
cnpg_instances: 2
cnpg_database_name: oil_tracker
cnpg_database_owner: oil_tracker
cnpg_storage_size: 5Gi
cnpg_storage_class: local-path
cnpg_node_selector:
  oilscope.io/cloud: azure
  oilscope.io/region: eastus
```

With `cnpg_instances: 2`, CloudNativePG creates one primary and one standby.
The role verifies that the selector matches at least two nodes before creating
the cluster. Required pod anti-affinity then places the instances on different
VMs in that cloud region.

Applications should use the stable writable endpoint:

```text
oilscope-postgres-rw.oilscope.svc.cluster.local:5432
```
