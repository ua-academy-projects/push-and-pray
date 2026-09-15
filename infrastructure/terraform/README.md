# Multi-cloud Terraform

Root reads project JSON once, configures providers, validates global
invariants, and connects provider modules. See [configuration ownership](../../docs/configuration.md).
Children receive structured inputs and never reopen the JSON file.

| Module | Responsibility |
| --- | --- |
| `network` | GCP VPC, subnets, router and NAT; historical address retained |
| `gcp_firewall` | GCP application ingress policy |
| `vm` | GCP VM filtering/mappings, instances, identities and public addresses |
| `aws_network` | AWS VPC, subnets, internet gateway, routing and optional NAT |
| `aws_security_groups` | AWS role security groups and ingress/egress policy |
| `aws_vm` | AWS VM filtering/mappings, AMIs, EC2, identities and Elastic IPs |
| `gcp_monitoring` | GCP CPU/HTTP dashboard, per-VM alerts and email notification channel |
| `aws_monitoring` | AWS CPU/health/HTTP dashboard, per-VM alarms and SNS email notifications |
| `gcp_managed_database` | Private-IP Cloud SQL PostgreSQL and service networking |
| `aws_managed_database` | Private RDS PostgreSQL, DB subnets and app-only security group |

`default_cloud` selects the provider for the complete deployment. `database_mode`
selects the independent runtime model: `self_hosted` preserves PostgreSQL on the
database VM and PGMQ; `managed` provisions PostgreSQL in the selected cloud,
keeps the database VM as the private RabbitMQ, Redis, and migration host, and distributes
generated credentials through the existing cloud secret stores. Self-hosted mode runs
PostgreSQL, PGMQ, and Redis on that VM. All modes reject per-VM cloud overrides that do
not match `default_cloud`, before resources are provisioned, because one bastion and the
private service paths require a single cloud.

VM modules are called once and iterate internally. Networks receive structured
network configuration; policy modules receive a shared policy object. Root
keeps placement needed by provider configuration and single-region networks.
Role, default/provider declaration, identity-label, naming, public-IP and CIDR
relationship checks remain global. Provider mapping, disk, zone and subnet-size
validation belongs to provider modules.

Monitoring is optional and defaults to disabled when `monitoring` is absent.
Set `monitoring.enabled` and `monitoring.cpu.enabled` to `true` to create a CPU
dashboard and one alert per Terraform-managed VM in each cloud that has VMs.
`monitoring.cpu.threshold_percent` defaults to `80` in Terraform when omitted
with the whole monitoring block, and `monitoring.cpu.duration_minutes` defaults
to `5`. Set `monitoring.notification_email` to the destination address. GCP
creates a Cloud Monitoring email channel, dashboard, and alert policies; AWS
creates an SNS topic/email subscription, CloudWatch dashboard, and alarms.
Confirm the subscription or verify the notification address if prompted by the
provider before expecting email delivery.

To change the CPU alert later, edit `threshold_percent` (for example, from `80`
to `20`) or `duration_minutes` in `project-config.json`, then review and apply a
new Terraform plan. Stable VM-keyed policies and alarms update in place; the
monitoring modules and dashboards are not recreated solely for that change.

Provider-neutral `vm_health` currently creates AWS `StatusCheckFailed` alarms
for Terraform-managed EC2 instances. Missing status-check data remains missing,
so these alarms detect EC2 impairment but not intentional stops. GCP has no
equivalent agentless metric: Google excludes terminated resources from metric-
absence evaluation and advises against using `instance/uptime` for availability.
Reliable GCP stopped-state detection requires a separate lifecycle-state design.

Provider-neutral `lifecycle` is separate from CPU and impairment monitoring.
GCP creates per-VM log-matched policies for explicit stop API calls and the
`hostError`, `guestTerminate`, and `terminateOnHostMaintenance` system events;
reset, start, and delete events are excluded. AWS uses one EventBridge EC2
state-change rule filtered to Terraform-managed instance IDs and the configured
`stopped`/`terminated` states, with the existing SNS topic as its target.

Set `monitoring.http_5xx.enabled` to monitor downstream HTTP 500-599 responses
returned by Traefik on the provider that hosts the UI VM. `threshold_count`
defaults to `5` responses in the `duration_minutes` window, which defaults to
`5`. GCP uses the `traefik_access` Cloud Logging stream, a log-based counter,
the existing Monitoring dashboard, and the existing email channel. AWS uses a
Terraform-managed `<prefix>-traefik-access` CloudWatch log group, a metric
filter, the existing CloudWatch dashboard, and the existing SNS/email path.
Re-run the UI Ansible playbook after applying the Terraform plan so the UI host
installs its provider-specific log agent and starts shipping the Traefik file.

Terraform owns secret containers and IAM grants. It derives IDs from
`application.secret_mappings`, keyed by application role. Only Ansible uses
the environment-variable names or fetches payloads. Persist the required
`secret_version_managers` list in an ignored local `*.auto.tfvars` file. Use
`[]` explicitly only for deployments without uploader grants. Omitting this
input must not silently revoke existing access.

## State safety

`migrations.tf` preserves the original network-count migration, GCP VM objects, and
extracted firewall rules. The managed AWS deployment is already stateful and live; never
remove state entries or accept replacements to conceal a migration mismatch. Mode-aware
local PostgreSQL ingress uses `moved` blocks so existing self-hosted rule addresses can be
adopted without recreation; in managed mode those unused infra-VM rules are intentionally
absent because PostgreSQL is private RDS/Cloud SQL instead.

Save a new plan and inspect it before applying:

```sh
terraform -chdir=infrastructure/terraform plan -input=false \
  -var='project_config_path=../../project-config.json' \
  -out="/tmp/oilscope-$(date +%s)-$$.tfplan"
```

VMs, IPs, networks, secrets and IAM must not be recreated. Adding bastion
startup metadata is an intentional in-place update. Keep plans out of Git;
never remove state entries to conceal migration failures.

## Bootstrap and images

Root renders SSH policy and passes optional `startup_scripts` keyed by VM key.
GCP uses `metadata["startup-script"]`, avoiding the replacement-triggering
`metadata_startup_script` argument. AWS combines SSH-user cloud-init with
optional `write_files` and `runcmd`. Scripts contain no secrets. Bastion first
boot configures port 8787; Ansible waits for that port and enforces the policy.
GCP runs the script on boot; AWS `runcmd` is a first-boot action. Changing AWS
user data is not a substitute for configuring an existing host.

GCP uses an image-family disk-initialization input directly, without a data
source polling for newer images; live plans retain existing disks/VMs. AWS
resolves the newest matching AMI for new instances but ignores `ami` changes
on existing instances. Intentional OS-image upgrades require a separately
reviewed replacement. A mocked create/plan test verifies AWS image retention.
See [GCP instance behavior](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)
and [AWS instance behavior](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance).

Supported disks are GCP `pd-standard`, `pd-balanced`, `pd-ssd` and AWS `gp2`,
`gp3`. Provider-default performance is sufficient; provisioned-IOPS disks and
an IOPS input are unsupported.

## Authentication and topology

Providers stay at root. Terraform initializes declared providers even for
empty resource collections. Conditional AWS placeholder credentials and skip
flags allow GCP-only plans without AWS credentials. They are enabled only for
zero AWS placements. Any AWS VM uses the normal real AWS credential chain.
Networks and secret resources follow the same provider selection, so the
placeholder branch cannot create AWS infrastructure.

Terraform and inventory support either cloud. Each configuration deploys one
communicating application in `default_cloud`: cross-cloud private networking is outside
scope, and mixed placement is rejected during Terraform validation.
Workloads use private SSH through the bastion. There is no direct public UI
SSH exception, VPN or transit routing. AWS private egress is disabled in the
example; the optional NAT Gateway is paid. Private application deployment
needs egress or suitable endpoints/mirrors for packages, images and secrets.

## Credential-free checks

```sh
python infrastructure/terraform/tests/generate_test_configs.py
python infrastructure/terraform/tests/validate_test_configs.py
terraform -chdir=infrastructure/terraform init -backend=false -input=false
terraform -chdir=infrastructure/terraform fmt -recursive -check
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform test
python -m unittest discover -s infrastructure/ansible/tests -v
git diff --check
```

Terraform tests mock providers, including the AMI lifecycle apply test; they
create no cloud resources. Controller tests use synthetic values and localhost
mock secret APIs. Generated fixtures stay under `.terraform`.
