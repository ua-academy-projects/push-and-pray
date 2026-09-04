# VM deployment operations

The supported deployment is controlled by Ansible. Each workload VM receives
`/opt/oilscope/app/compose.yaml` for its own role. The UI VM also receives the
Traefik project under `/opt/oilscope/proxy`.

There is no `oilscope-deploy.service`, shared `compose.deployment.yaml`, or
persistent `deployment.env` in the current Ansible path. Runtime secrets are
supplied only while Ansible invokes Compose.

## Check workload status

Connect to the VM through the bastion and list containers belonging to the
application project:

```sh
docker ps --all \
  --filter label=com.docker.compose.project=petroscope \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

On the UI VM, inspect the edge proxy separately:

```sh
docker ps --all \
  --filter label=com.docker.compose.project=oilscope-proxy \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

Check the container health status used by the Ansible roles:

```sh
docker inspect \
  --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
  <container-name>
```

History also publishes its health endpoint on the VM's private interface, so
`curl --fail http://127.0.0.1:8001/health` is available on the History VM.
Ansible validates Fetcher and UI through their container health status rather
than relying on a host-side HTTP request.

## Read logs

First obtain the container name with `docker ps`, then read its logs directly.
This does not require reconstructing the secret environment used during
deployment:

```sh
docker logs <container-name>
docker logs --follow <container-name>
docker logs --since 1h <container-name>
```

Typical names are derived from the `petroscope` project and the service name,
for example `petroscope-history-1`. Always use the name reported by Docker
rather than assuming it.

## Redeploy or restart a workload

Redeploy from the Ansible controller. This re-resolves secrets, authenticates
to the registry, pulls the configured immutable image SHA, starts the role, and
waits for its health check:

```sh
ansible-playbook oilscope.platform.history \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

Replace `history` with `database`, `fetcher`, or `ui` as needed. Use
`oilscope.platform.deploy_workloads` when dependencies also need to be
reapplied in order.

For an immediate restart that does not pull or re-render configuration, use
the exact container name reported by `docker ps`:

```sh
docker restart <container-name>
```

## Stop a workload

Stop the role's container without removing its volume or configuration:

```sh
docker stop <container-name>
```

Running the corresponding Ansible playbook starts it again. On the Database
VM, do not remove the `petroscope_postgres_data` volume unless permanent data
deletion is explicitly intended.
