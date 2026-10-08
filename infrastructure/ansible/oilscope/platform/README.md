# Ansible Collection - oilscope.platform

Documentation for the collection.

## Validate configuration

Before deploying, validate your project configuration file against the schema:

​```bash
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
​```

## Deploy all workloads

Deploy the application workloads in dependency order. First, export the selected
database connection from the Terraform state as an Ansible extra-vars file:

```bash
terraform -chdir=infrastructure/terraform output -json \
  | jq '{database_connection: .database_connection.value, messaging_connection: .messaging_connection.value, session_connection: .session_connection.value}' \
  > /tmp/oilscope-database-connection.json
```

The generated file contains non-secret database, queue, and session-store connection
metadata, including the selected providers and private hosts. It contains no passwords.

Then run the deployment:

- `self_managed`: the infra VM runs PostgreSQL with PGMQ and PostgreSQL-backed sessions.
- `managed`: Cloud SQL/RDS stores application data while the infra VM runs RabbitMQ and Redis.

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e @/tmp/oilscope-database-connection.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Deploy to Amazon EKS

Apply the EKS Terraform configuration, export the non-secret connection output,
then run the local-controller playbook. It writes an isolated kubeconfig at
`~/.cache/oilscope/eks/kubeconfig` and never changes the default kubeconfig.

```bash
terraform -chdir=infrastructure/terraform output -json aws_kubernetes \
  | jq '{eks_platform_connection: .}' > /tmp/oilscope-eks.json
ansible-playbook oilscope.platform.deploy_eks -i localhost, \
  -e project_config_path=/absolute/path/project-config.json \
  -e @/tmp/oilscope-eks.json
```

Pass the output as `eks_platform_connection` when invoking Ansible. The AWS CLI
identity must be listed in `kubernetes.eks.administrator_principal_arns`; the
controller also requires `kubectl` and Helm.

## Deploy to Google Kubernetes Engine

GKE Standard uses a dedicated local kubeconfig at
`~/.cache/oilscope/gke/kubeconfig`. Terraform creates the VPC-native Pod and
Service CIDR ranges, a three-node `e2-medium` pool, GKE Cloud Operations,
Persistent Disk CSI, Artifact Registry access, a global ingress IP, and the
Cloudflare A record. The local controller requires authenticated `gcloud`,
`kubectl`, and Helm.

```bash
terraform -chdir=infrastructure/terraform output -json gcp_gke \
  | jq '{gke_platform_connection: .}' > /tmp/oilscope-gke.json
ansible-playbook oilscope.platform.deploy_gke -i localhost, \
  -e project_config_path=/absolute/path/project-config.json \
  -e @/tmp/oilscope-gke.json
```

Run the Terraform apply before the playbook. The Google-managed certificate is
provisioned only after the Cloudflare A record resolves to the static ingress
IP; certificate activation can take several minutes.
