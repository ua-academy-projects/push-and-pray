# Ansible Collection - oilscope.platform

Documentation for the collection.

## Validate configuration

Before deploying, validate your project configuration file against the schema:

​```bash
uvx check-jsonschema \
  --schemafile project-config.schema.json \
  /absolute/path/project-config.json
​```

## Deploy all workloads

Deploy the application workloads in dependency order:

1. Database
2. History
3. Fetcher
4. UI

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Upload secret versions

Terraform creates the AWS and GCP secret containers, but it does not store
their values. Validate and upload values from the controller environment with:

```bash
ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

See [docs/secrets.md](../../../../docs/secrets.md) for provider requirements,
source variable naming, and rotation guidance.

## Configure GCP observability

After Terraform grants the GCP VM service accounts their Logging and Monitoring
writer roles, install the Ops Agent on the existing VMs with:

```bash
ansible-playbook oilscope.platform.configure_gcp_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook exports host metrics from every GCP VM and collects Docker JSON
logs from workload VMs. It does not restart the application containers. See the
[`gcp_ops_agent` role](roles/gcp_ops_agent/README.md) for details.

## Configure AWS observability

After Terraform attaches the CloudWatch Agent policy to the EC2 instance
roles, install and configure the agent on the existing instances with:

```bash
ansible-playbook oilscope.platform.configure_aws_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook publishes host metrics to the `OilScope` CloudWatch namespace,
sends system logs from every AWS instance, and sends Docker JSON logs from
workload instances. It does not restart the application containers. See the
[`aws_cloudwatch_agent` role](roles/aws_cloudwatch_agent/README.md) for details.
