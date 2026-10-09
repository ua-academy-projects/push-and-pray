# CloudNativePG

Installs the CloudNativePG operator from its Helm chart into `cnpg-system`.

The operator is not a database. It adds the `Cluster` resource type (and
`Backup`, `Pooler` and others) to Kubernetes and watches every namespace for
them: given a `Cluster`, it creates the PostgreSQL pods, their volumes, the
replication between them, the Services that point at the primary and at the
replicas, and a Secret with the application's credentials - and it promotes a
replica when the primary goes away. The `database` role writes that `Cluster`.

`wait: true` matters: the role that follows creates a `Cluster`, a type that
exists only once the chart's CRDs are installed and the operator's webhook
answers.

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `cloudnative_pg_kubeconfig` | `oilscope_kubeconfig` | Kubeconfig on the controller |
| `cloudnative_pg_version` | — | Chart version, from `cluster.charts.cloudnative_pg.version` |
| `cloudnative_pg_namespace` | `cnpg-system` | Namespace of the operator |
| `cloudnative_pg_repo_url` | `https://cloudnative-pg.github.io/charts` | Chart repository |

The chart's own defaults are used as they are, so there is no values file:
one operator replica is enough for this cluster.

## License

GPL-2.0-or-later
