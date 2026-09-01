# AWS VM

The AWS half of the VM contract: one EC2 instance with its own IAM role, a
static internal address, and optionally a static public one. It accepts the
same variables as `modules/gcp/vm` and returns the same outputs.

## Differences worth knowing

**The AMI is looked up, not pinned.** An AMI ID differs per region and changes
with every Canonical release, so `image` carries a name pattern and a data
source resolves the current match. GCP resolves the equivalent token to an
image family, which the provider does for us.

**SSH accounts come from cloud-init.** Compute Engine accepts public keys
through instance metadata; EC2 has no equivalent channel. The module renders a
minimal cloud-config that creates the accounts and installs the keys, and
nothing else. Docker and the application stay with Ansible.

**IMDSv2 is required.** `resolve_secrets` reads the instance identity from the
metadata service, and a v1 endpoint is reachable by anything that can make the
VM issue a request on its behalf.

**Provisioned IOPS are conditional.** The portable `ssd` token resolves to
`io2` here, and AWS refuses an io1 or io2 volume that does not state its IOPS -
a requirement `terraform validate` cannot see, because the field is optional in
the schema. The module supplies `boot_disk_iops` for those two types and leaves
it unset for gp2 and gp3, which derive it from the volume size.

**Runtime identity is an IAM role.** The GCP module gives each VM its own
service account so secret access can be granted per workload; here that is a
role and an instance profile. The root module attaches the secret policies to
it, exactly as it binds IAM members to the service account.

## Variables

Identical to `modules/gcp/vm`: `name`, `role`, `subnet_id`, `network_groups`,
`machine_type`, `image`, `internal_ip`, `boot_disk_size_gb`, `boot_disk_type`,
`assign_public_ip`, `labels`, `ssh_users`. Plus `image_owner`, which defaults
to Canonical, and `boot_disk_iops`, which defaults to the minimum AWS accepts.
Both have defaults, so the root module passes the same arguments to either
cloud.

`machine_type`, `image` and `boot_disk_type` arrive already resolved from their
portable tokens - the module never sees `micro` or `balanced`.

## Outputs

`name`, `internal_ip`, `public_ip`, `network_groups`, `runtime_identity`, and
`runtime_identity_arn` for attaching policies.
