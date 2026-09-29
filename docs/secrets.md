# Secrets

Application credentials live in the selected cloud secret manager. For Compose,
Terraform manages containers and VM access; for K3s, it creates the containers
without giving every node application-secret access. Ansible manages values and
delivers them to the relevant VM or Kubernetes namespace. Application secret
versions do not pass through Terraform configuration, plans, or state. The
password used to create a managed PostgreSQL database is the one exception
described below.

## Configuration model

Each VM declares the application variable name and secret container ID:

```json
"secret_mappings": {
  "POSTGRES_PASSWORD": "db-password",
  "GHCR_TOKEN": "ghcr-token"
}
```

Both strings are identifiers, not secrets. The key is the variable consumed by
the application on that VM. The value is the container ID in AWS Secrets
Manager or Google Secret Manager, or the Azure Key Vault secret name.

Mappings must describe only the services used by the selected database
architecture. Self-managed database deployments use PostgreSQL for PGMQ and UI
sessions, so they do not map RabbitMQ or Redis secrets. Managed database
deployments additionally map
`RABBITMQ_PASSWORD` on the Infrastructure, History, and Fetcher VMs and
`REDIS_PASSWORD` on the Infrastructure and UI VMs.

Terraform derives the containers and workload read grants from this mapping.
The same container ID may be shared by several VMs in one provider scope. AWS
containers are regional, so the effective VM location determines the region;
GCP containers are scoped to `cloud_settings.gcp.project_id`. On Azure, each
workload with mappings receives the Key Vault Secrets User role at vault scope;
secret-level scopes cannot be assigned before automation creates the secrets.

K3s mode declares the same kind of identifier mapping once at cluster level:

```json
"k3s": {
  "secret_mappings": {
    "POSTGRES_PASSWORD": "db-password",
    "RABBITMQ_PASSWORD": "rabbitmq-password",
    "RABBITMQ_ERLANG_COOKIE": "rabbitmq-erlang-cookie",
    "REDIS_PASSWORD": "redis-password",
    "OILPRICEAPI_KEY": "external-api-key",
    "GHCR_TOKEN": "ghcr-token"
  }
}
```

For the current GCP K3s deployment, Terraform creates these Secret Manager
containers without granting every cluster VM direct application-secret access.
The local controller reads the values with the operator's `gcloud` identity and
creates namespace-scoped Kubernetes Secrets through the private API endpoint.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| Terraform AWS secrets module | Create regional containers, EC2 roles and instance profiles, and `GetSecretValue` policies |
| Terraform GCP secrets module | Create project containers and VM service accounts, and grant secret accessor membership |
| Terraform Azure secrets module | Create a Key Vault and workload managed identities, and grant vault secret-reader roles; secret values and names are created later by automation |
| `secret_versions` Ansible role | Reconcile environment values with the latest enabled versions in every required cloud and scope |
| `resolve_secrets` Ansible role | Read only the current VM's mapped values through its attached cloud identity |
| `k3s_secrets` Ansible role | Read K3s values from GCP on the controller and reconcile the application and GHCR pull Secrets in the configured namespace |

Terraform deliberately creates no secret versions. Creating a managed database
is the one exception to the Ansible-only value flow: set the ephemeral
`TF_VAR_database_password` variable to the same value as `DB_PASSWORD`.
The managed database resources use provider write-only password arguments, so
the value is not retained in Terraform plans or state.

The deployment applies this password when a managed database is created. It
does not support rotating the password of an existing managed database in
place; recreate the development database when changing `DB_PASSWORD`. The
providers require an internal write-only password version, which is fixed at
`1` in Terraform and is not a project configuration option.

The Azure Terraform path creates the Key Vault and access roles but no secret
objects because an Azure Key Vault secret cannot exist without a value. The
first Ansible synchronization creates each mapped secret and its initial
version; later synchronizations add a version only when its value changes.

## Uploading values

The upload role derives its source variable from the container ID by converting
it to upper case and replacing non-alphanumeric characters with underscores:

```text
db-password      -> DB_PASSWORD
ghcr-token       -> GHCR_TOKEN
external-api-key -> EXTERNAL_API_KEY
```

One source value is uploaded to every cloud/scope target that references that
container ID. Use different container IDs when different clouds or workloads
must receive different values.

The controller needs the corresponding provider toolchain for every cloud in
the configuration:

- AWS: boto3 in Ansible's Python and normal AWS credential resolution, such as
  `AWS_PROFILE`.
- Azure: an authenticated Azure CLI session, normally established with
  `az login` and the subscription selected by the project configuration.
- GCP: an authenticated `gcloud` session.

The operator also needs permission to describe containers, read current
versions, and add versions. Terraform's workload-reader policies do not grant
operator synchronization access.

Load the desired values from their independent recovery source. Reuse those
values on repeated deployments; running the random-generation commands again
requests a rotation. The general deployment reads the latest enabled value and
adds a version only when the corresponding environment value differs:

```bash
export DB_PASSWORD="..."
export GHCR_TOKEN="..."
export EXTERNAL_API_KEY="..."

# Managed database only:
export RABBITMQ_PASSWORD="..."
export REDIS_PASSWORD="..."

ansible-playbook oilscope.platform.deploy \
  -i infrastructure/ansible/inventory/oilscope.yml
```

For K3s, also provide the RabbitMQ Erlang cookie and then use the explicit
secret upload and cluster synchronization playbooks. The general Compose
deployment playbook is not used:

```bash
export DB_PASSWORD="..."
export RABBITMQ_PASSWORD="..."
export RABBITMQ_ERLANG_COOKIE="..."
export REDIS_PASSWORD="..."
export EXTERNAL_API_KEY="..."
export GHCR_TOKEN="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"

# Keep the bastion SSH tunnel to 127.0.0.1:6443 running first.
ansible-playbook oilscope.platform.synchronize_k3s_secrets \
  -i localhost, \
  -e k3s_secrets_config_file="$PWD/project-config.json"
```

The synchronization creates `<name-prefix>-application` with application/data
service credentials and `<name-prefix>-registry` with the GHCR Docker
configuration. Secret-bearing Ansible tasks use `no_log`; the plaintext values
are held in controller memory while the role runs and are stored as Kubernetes
Secret data in the cluster.

To force a new version for a deliberate API-key rotation, select that container
explicitly with the upload playbook:

```bash
export EXTERNAL_API_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["external-api-key"]}' \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["external-api-key"]}'
```

The upload playbook does not consume `TF_VAR_database_password` and cannot change
the password on an existing database. For a self-managed database, PostgreSQL
also does not change an initialized user's password when the container's
`POSTGRES_PASSWORD` environment value changes. Therefore, do not rotate
`DB_PASSWORD` with the upload playbook alone. Database password rotation requires
a separate coordinated procedure that changes PostgreSQL and its secret value.

Check mode verifies source variables, target containers, and current-version
read access without writing. The normal run passes payloads through stdin
without an added newline. Tasks that compare or otherwise handle values use
`no_log`. All containers are checked before uploads start, although a provider
failure during the write phase can still result in a partial rotation.

Rotate a subset by container ID or derived source variable:

```bash
ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["external-api-key"]}'
```

## Reading values during deployment

The workload playbooks invoke `resolve_secrets` on each VM. The dynamic
inventory identifies the exact VM key and cloud, and the role selects only that
VM's mappings.

- On AWS, boto3 uses the attached EC2 instance profile and reads from the VM's
  effective region.
- On Azure, the role obtains a Key Vault token from the Instance Metadata
  Service through the VM's user-assigned managed identity and reads the current
  secret version from the deployment's vault.
- On GCP, the role obtains a token for the attached service account from the
  metadata server and reads the `latest` version from Secret Manager.

The result is an in-memory `resolve_secrets_result` dictionary keyed by the
application variable names. The role does not intentionally write values to
disk. Subsequent application roles must preserve the same care when passing
those values to services or configuration files.

## Rotation and recovery

Adding a version leaves older versions in place. Restart consumers so they read
the new `latest` version, verify the deployment, and only then disable or destroy
the previous version according to the provider's recovery model.

For K3s consumers, rerun `synchronize_k3s_secrets` after adding the version,
then perform a controlled rollout of the workloads that consume the changed
Secret. Updating a Kubernetes Secret does not automatically restart Pods.

If a value leaks, create a replacement version first, redeploy consumers, then
disable or destroy the exposed version. Removing a leaked value from Git or a
log does not make the credential safe again.

Destroying Terraform-managed secret containers can also remove their versions
or schedule them for deletion. Keep an independent recovery source for values
needed after infrastructure teardown.
