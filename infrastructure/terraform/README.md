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

VM modules are called once and iterate internally. Networks receive structured
network configuration; policy modules receive a shared policy object. Root
keeps placement needed by provider configuration and single-region networks.
Role, default/provider declaration, identity-label, naming, public-IP and CIDR
relationship checks remain global. Provider mapping, disk, zone and subnet-size
validation belongs to provider modules.

Terraform owns secret containers and IAM grants. It derives IDs from
`application.secret_mappings`, keyed by application role. Only Ansible uses
the environment-variable names or fetches payloads. Persist the required
`secret_version_managers` list in an ignored local `*.auto.tfvars` file. Use
`[]` explicitly only for deployments without uploader grants. Omitting this
input must not silently revoke existing access.

## State safety

`migrations.tf` preserves the original network-count migration, 12 GCP VM
objects and five extracted firewall rules. No AWS resources existed in the
reviewed deployment. Review addresses and add corresponding moves before
using this refactor with any unrelated existing AWS state.

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

Terraform and inventory support both clouds. Deploy one communicating
application in one cloud: cross-cloud private networking is outside scope.
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
