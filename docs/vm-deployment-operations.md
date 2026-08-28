# VM deployment operations

Terraform creates clean OilScope virtual machines, networking, service
accounts, labels and SSH public-key metadata. It does not install Docker or
start the application. Bastion SSH configuration and workload deployment are
owned by the `oilscope.platform` Ansible collection.

## Controller setup

Install the inventory dependencies and build the local collection:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
ansible-galaxy collection build infrastructure/ansible/oilscope/platform
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
gcloud auth application-default login
```

The commands below use these values:

```sh
inventory=infrastructure/ansible/inventory/oilscope.gcp.yml
project_config=/absolute/path/project-config.json
```

Keep the project config outside the repository and pass an absolute path.

## Authenticate to private GHCR images

The project configuration keeps the non-secret GitHub username in
`registry.username`. Every workload maps `GHCR_TOKEN` to the same Secret
Manager container; the bastion has no access to it. Terraform creates that
container and grants each workload service account `secretAccessor`, but never
receives or stores the token value.

The no-argument GCP deployment reads `GHCR_USERNAME` and `GHCR_TOKEN` from the
ignored `.env` file. When they are absent, it reads the existing `ghcr.io`
login through Docker's configured credential helper. It uploads the token to
Secret Manager through standard input before Ansible starts.

During deployment, `oilscope.platform.registry_auth` uses each VM's identity to
read the token. It first checks the exact database image and runs
`docker login ghcr.io --password-stdin` only when existing access fails. The
secret-bearing task uses `no_log`, and Docker stores the resulting credential
under the root-only `/root/.docker` directory because image pulls run with
`become`.

For a manual deployment, make sure the configured GHCR secret already has a
version before running `oilscope.platform.deploy`. A successful repeated run
skips login after the manifest access check succeeds.

## Bootstrap a fresh bastion

A fresh Ubuntu bastion initially accepts SSH on port 22. Terraform permits
that bootstrap port and the configured port only from
`vms.bastion.allowed_cidrs`. The bootstrap playbook connects through port 22,
applies `oilscope.platform.bastion`, and verifies a new Ansible connection on
`vms.bastion.ssh_port`:

```sh
ansible-playbook oilscope.platform.bootstrap_bastion \
  -i "$inventory" \
  -e project_config_path="$project_config"
```

Run this playbook once for a fresh bastion. Normal inventory connections read
the configured bastion port from the same project config.

## Verify management connectivity

Verify the bastion first, then all private workload hosts through its
`ProxyCommand`:

```sh
ansible bastion -i "$inventory" \
  -e project_config_path="$project_config" \
  -m ansible.builtin.ping

ansible workloads -i "$inventory" \
  -e project_config_path="$project_config" \
  -m ansible.builtin.ping
```

## Deploy the application

The collection deployment playbook applies the host baseline, installs Docker
and the non-secret Compose project, authenticates every workload to private
GHCR images, then deploys Database and migrations before History, Fetcher and
UI:

```sh
ansible-playbook oilscope.platform.deploy \
  -i "$inventory" \
  -e project_config_path="$project_config"
```

Runtime secret values are read on each workload VM with its own service account
and are passed directly to the service roles. They are not stored in Terraform
metadata or deployment files.

Run the deployment smoke test after every fresh deployment:

```sh
ansible-playbook oilscope.platform.smoke_test \
  -i "$inventory" \
  -e project_config_path="$project_config"
```

The smoke test requires one host in each of `bastion`, `database`, `history`,
`fetcher` and `ui`. It verifies PostgreSQL and the three application service
health contracts.

## Confirm idempotency

Run `oilscope.platform.deploy` a second time with the same inventory, project
config and image SHA. Review the play recap and every changed task. Health
checks, secret reads, unchanged files and already-running containers must not
report changes. A container recreation is expected only when its image or
effective configuration changed.

## Inspect and operate containers

Each workload uses `/opt/oilscope/app/compose.yaml` and the Compose project name
`petroscope`:

```sh
sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  ps

sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  logs <service>
```

Use `postgres` and `migrate` on the Database VM, or `history`, `fetcher` and
`ui` on their corresponding hosts. Re-run the collection deployment playbook
for normal deployment or recovery instead of relying on a boot-time systemd
deployment unit.
