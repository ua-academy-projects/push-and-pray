# Registry authentication role

Authenticates a workload VM to a private container registry for the duration
of one deployment play. The role reads `GHCR_USERNAME` and `GHCR_TOKEN` from
the Ansible controller environment, passes the token to `docker login` through
standard input, and stores Docker's generated configuration only under `/run`.

## Variables

- `registry_auth_registry`: registry hostname; defaults to `ghcr.io`.
- `registry_auth_username`: defaults to the controller's `GHCR_USERNAME`.
- `registry_auth_token`: defaults to the controller's `GHCR_TOKEN`.
- `registry_auth_docker_config_dir`: transient Docker configuration directory;
  defaults to `/run/oilscope/docker-auth`.

## Security behavior

- Token-bearing tasks use `no_log: true`.
- The token is sent to `docker login` with `--password-stdin`.
- The transient directory is owned by root with mode `0700`.
- A failed login removes the directory immediately.
- A successful login notifies a cleanup handler. Deployment plays using this
  role set `force_handlers: true`, so a later workload failure still removes
  the credentials.
- No registry token is written to project configuration, Ansible defaults,
  Compose templates, Terraform state, or a cloud secret manager.

The workload role that follows this role must pass
`registry_auth_docker_config_dir` as `DOCKER_CONFIG` to every command that may
pull an image.

## License

GPL-2.0-or-later
