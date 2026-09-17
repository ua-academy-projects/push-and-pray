# Edge proxy role

Creates the shared Docker network and starts the Traefik edge proxy installed on
the UI VM.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/proxy/compose.yaml` is installed by the
  `oilscope.platform.compose_project` role with the `proxy` workload.
- The UI workload configuration provides the public hostname and ACME email.

## Variables

- `edge_proxy_dir`: proxy project directory; defaults to
  `/opt/oilscope/proxy`.
- `edge_proxy_compose_file`: Compose definition; defaults to `compose.yaml` in
  the proxy directory.
- `edge_proxy_compose_project_name`: Compose project name; defaults to
  `oilscope-proxy`.
- `edge_proxy_network_name`: shared external network used by Traefik and the UI;
  defaults to `oilscope-edge`.

The role creates the shared network when absent, installs Traefik's dynamic
routing configuration, preserves an existing `acme.json`, and waits for Traefik
to start successfully. Repeated runs reconcile the same resources.

## License

GPL-2.0-or-later
