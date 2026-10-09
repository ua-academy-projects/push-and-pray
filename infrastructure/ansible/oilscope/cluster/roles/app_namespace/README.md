# App namespace

Creates the namespace the application and its data services share, and the
Secret that lets their pods pull private images from GHCR.

## What it creates

| Resource | Purpose |
| --- | --- |
| `Namespace/<oilscope_namespace>` | Home of the database, Redis and later the application |
| `Secret/ghcr-pull` | `kubernetes.io/dockerconfigjson` with the GHCR username and token; pods list it under `imagePullSecrets` |

The token is the `GHCR_TOKEN` secret, resolved on a `k3s_server` node by
`resolve_secrets` and handed over in memory. The task writing it is `no_log`.

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `app_namespace_kubeconfig` | `oilscope_kubeconfig` | Kubeconfig on the controller |
| `app_namespace_name` | `oilscope_namespace` | Namespace to create |
| `app_namespace_registry` | `ghcr.io` | Registry the credentials are for |
| `app_namespace_registry_username` | — | `registry.username` from the configuration |
| `app_namespace_registry_token` | — | The `GHCR_TOKEN` value |
| `app_namespace_pull_secret` | `ghcr-pull` | Name of the pull Secret |

## License

GPL-2.0-or-later
