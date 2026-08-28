# Registry authentication role

Authenticates root-owned Docker commands to a private container registry. The
role first checks the exact deployment image and skips login when existing
credentials already work.

The token is passed to `docker login` only on standard input. The login task
uses `no_log`, so the token does not appear in Ansible output or process
arguments. Docker stores the resulting credential in the root-only
`/root/.docker` directory because deployment image pulls run with `become`.

## Required variables

- `registry_auth_registry`: registry hostname; defaults to `ghcr.io`.
- `registry_auth_username`: non-secret registry username.
- `registry_auth_token`: token read from the workload's Secret Manager access.
- `registry_auth_probe_image`: immutable image used to verify registry access.

## Optional variables

- `registry_auth_config_dir`: Docker credential directory; defaults to the
  root-only `/root/.docker` path used by the deployment's privileged image
  pulls.

## Repeated runs

The role checks `registry_auth_probe_image` with the configured Docker directory
before logging in. If the manifest is already accessible, directory creation
and login are skipped. It always performs a final manifest check so expired or
insufficient credentials fail before a service role starts pulling images.

## License

GPL-2.0-or-later
