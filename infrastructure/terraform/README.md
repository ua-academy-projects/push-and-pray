# Terraform infrastructure

The root reads one external JSON and calls small modules directly.
Root `locals.tf` loads that JSON and derives shared database/queue runtime
metadata from the selected database workload and `database_mode`.
Modules do not call other modules. Root passes subnet IDs, security-group IDs,
and runtime identities between them; these resource dependencies are necessary.

| Module | Responsibility |
| --- | --- |
| aws-network | VPC, subnets, Internet Gateway and routing |
| aws-security | Per-VM security groups and traffic rules |
| aws-vm | EC2, SSH key pair and optional additional disks |
| aws-rds | Private RDS PostgreSQL, DB subnet group and least-privilege ingress |
| aws-secrets | AWS application secret containers and generated RabbitMQ credential |
| gcp-network | VPC, subnets, router and Cloud NAT |
| gcp-security | GCP firewall rules |
| gcp-vm | Compute Engine instances, public IPs and optional disks |
| gcp-cloud-sql | Private Cloud SQL PostgreSQL and its credential secret |
| iam | AWS EC2 role/profile and GCP service accounts |
| gcp-apis | Enable GCP services when GCP VMs are selected |
| gcp-secrets | GCP secret containers and scoped IAM grants |

## Database modes

`database_mode` defaults to `self_hosted`.

- `self_hosted` keeps PostgreSQL 18 and PGMQ on the existing database VM.
- `managed` creates RDS when the database VM selects AWS, or Cloud SQL when it
  selects GCP. The former database VM keeps its disk, stops its PostgreSQL
  container, runs RabbitMQ, and acts as the private migration runner.

The database VM and all database clients must select the same cloud because no
cross-cloud private routing is created. See
[managed database operations](../../docs/managed-database.md).

## Choosing a location

Keep the real file at `config/dev.json` or pass another external path.
The sanitized example is `../../project-config.example.json`.
Each cloud has five named locations:

| Key | AWS region | GCP region |
| --- | --- | --- |
| europe-west | eu-west-1 | europe-west1 |
| europe-central | eu-central-1 | europe-west3 |
| america-east | us-east-1 | us-east1 |
| america-west | us-west-2 | us-west1 |
| asia-southeast | ap-southeast-1 | asia-southeast1 |

Set both keys together:
```json
"location": {
  "region": "europe-west",
  "zone": "europe-west"
}
```

The `default` dictionary entries preserve the previous region and zone.
They are aliases, not extra deployments. One location is selected per run;
adding dictionary entries does not create resources in every region.
Changing location on an existing state can replace resources: inspect the plan.
Independent regional deployments need separate configs and backend prefixes.

`default_cloud` and optional `vms.<name>.cloud` still select the provider.
No VPN or cross-cloud routes are created. A module with no matching VMs has
no managed resources. Provider/backend authentication is a separate requirement.

## Images and addresses

`clouds.<cloud>.images.<location-key>.<image-key>` resolves each VM's `image`.
The dictionaries include Ubuntu 24.04 and 22.04. AWS values may be a region-local
AMI ID or a public Canonical SSM path; lookup uses the selected AWS provider region.
SSM `current` and GCP image families track upstream updates; use an exact AMI
or image version when the OS image must be pinned. Availability has not been
verified against a live cloud account. Machine-size dictionaries are unchanged.

AWS has optional `clouds.aws.network` overrides and per-VM `internal_ips.aws`.
The examples use an AWS management /28 and valid private addresses, preserving
the existing GCP network and addresses. AWS reserves the first four addresses
and the last address in each subnet; AWS IPv4 subnets must be /28 or larger.

## Optional disks and dynamic blocks

Add an optional map to a VM:
```json
"additional_disks": {
  "data": {
    "device_names": { "aws": "/dev/sdf", "gcp": "data" },
    "size_gb": 20,
    "type": "balanced"
  }
}
```

No additional disks are enabled in dev/example by default.
AWS uses dynamic `ebs_block_device`; GCP creates disks with `for_each`
and uses dynamic `attached_disk`. GCP's optional public address uses
dynamic `access_config`. Filesystems and mounts remain an Ansible task.
Removing a managed disk from configuration may delete it; inspect the plan
and back up its contents first.

## SSH and secrets

The existing `enable_bastion_ssh_bootstrap` flag opens temporary port 22
for the allowed bastion CIDRs in either cloud. After Ansible configures the
final port, disable the flag and review/apply the firewall change.
AWS attaches the first sorted SSH public key to the image's Ubuntu user.
GCP metadata contains the configured Linux usernames and keys.
Private keys remain on the operator's host.

The IAM module uses native resources; it does not wrap the Babenko module.
In managed AWS mode, the EC2 role can read only the project and RDS credential
secrets. GCP secret access is scoped to configured service accounts. RDS owns
its master password; Cloud SQL and RabbitMQ credentials are generated by
Terraform and stored only in the encrypted Terraform state and cloud secret
manager, never in Git or ordinary outputs. Managed AWS database mode creates a
NAT Gateway for private workload egress by default; disable it only when another
image-delivery path exists.

## Cloudflare UI DNS

Set `cloudflare_zone_id` and put the API token in the ignored local
`config/dev.json` file under `cloudflare.api_token`. The token needs Zone DNS
Edit permission for that zone. Terraform then manages one proxied `A` record
using `vms.ui.public_endpoint.hostname` and the current public IP of the UI VM,
regardless of whether that VM is in AWS or GCP.

```bash
terraform -chdir=infrastructure/terraform plan \
  -var='cloudflare_zone_id=0123456789abcdef0123456789abcdef'
```

If the DNS record already exists outside Terraform, import it once before the
first apply instead of creating a second record:

```bash
terraform -chdir=infrastructure/terraform import \
  'cloudflare_dns_record.ui[0]' \
  '<zone_id>/<dns_record_id>'
```

## Before deployment

This restructuring changes Terraform addresses. See
[the state migration checklist](../../docs/terraform-module-migration.md)
before planning against existing infrastructure. No state was migrated and
`moved.tf` has not been recreated.

Run offline configuration checks from the repository root:
```sh
python -m unittest discover -s scripts/tests -p test_infrastructure_config.py
```

When ready, separately run formatting, initialization, validation and a reviewed
plan using the correct existing backend and real JSON. These cloud/backend
operations were not run while editing. Ansible inventory uses the same
location dictionaries; set `OILSCOPE_PROJECT_CONFIG` to the same JSON path.

References: [Terraform dynamic blocks](https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks),
[AWS subnet sizing](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html),
[Canonical AWS image lookup](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/).
