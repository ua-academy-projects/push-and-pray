# Deploying to more than one cloud

The same stack, the same five roles and the same playbooks go up in GCP or in
AWS. Which cloud is a field in the project configuration, not a property of the
code.

```json
{ "default_cloud": "gcp", "location": "us-east", ... }
```

`default_cloud` covers every VM. A VM may name a different one for itself:

```json
"vms": {
  "bastion": { "cloud": "aws", ... },
  "infra":   { ... }
}
```

The second form exists so the mechanism does not assume one cloud per
deployment. Splitting an application across clouds needs a network between
them, which this project does not have, so in practice every VM usually takes
the default. What the per-VM field buys is a VM that genuinely belongs
elsewhere - something reaching the service from outside, for instance.

## Where the abstraction lives

Two places, and neither of them is inside a module.

**The configuration speaks in intent.** `size: micro`, `os: ubuntu-26.04`,
`boot_disk.type: balanced`, `location: us-east`. None of those strings is a
provider identifier, and none of them changes with the cloud.

**The root module translates.** `catalog.tf` holds one table per translatable
concept, keyed by cloud, and every value is resolved with `lookup`:

| Portable token | GCP | AWS |
| --- | --- | --- |
| `size: micro` | `e2-micro` | `t3.micro` |
| `boot_disk.type: balanced` | `pd-balanced` | `gp3` |
| `boot_disk.type: ssd` | `pd-ssd` | `io2` |
| `location: us-east` | `us-east1` / `us-east1-b` | `us-east-1` / `us-east-1a` |

The table lives in the repository rather than in a configuration file on
purpose: a configuration picks from a fixed menu, and the menu is owned by the
team. Adding a cloud is adding a column, not editing any deployment.

`validation.tf` checks every token before a provider is called, so a typo names
itself and lists what was allowed instead of surfacing as `Invalid index` from
somewhere inside a module.

## What cannot be translated

Some things are not the same concept under two names. Compute Engine network
tags and EC2 security groups both restrict traffic, but one is a string on an
instance and the other is a resource referenced by ID. A lookup table cannot
bridge that, and pretending otherwise produces the worst version of both.

Those live in the modules, and the abstraction is the **module interface**:
`modules/gcp/vm` and `modules/aws/vm` accept the same variables and return the
same outputs. The root passes `network_groups` and reads `runtime_identity`
without knowing whether it just handed over a network tag or a security group
ID, a service-account email or an IAM role name.

Anything genuinely cloud-specific sits in its own configuration section - `gcp`
for the project ID, `aws` for the account and its regions - so it never
pretends to be portable.

## What is not hardcoded at all

An AMI ID differs per region and changes with every Canonical release. Putting
one in a configuration file or a lookup table guarantees a break within weeks,
so the portable `os` token resolves to a **name pattern** and the AWS module
looks the current AMI up with a data source. GCP resolves the same token to an
image family, which is the same idea served by the provider.

## Which modules run

A cloud's modules are created when at least one VM targets it. Nothing is
declared twice and nothing is indexed with `[0]`:

```hcl
module "aws_vm" {
  source   = "./modules/aws/vm"
  for_each = local.aws_vms       # {} when no VM targets aws
}
```

Both providers are declared and the unused one performs no API call, because
Terraform only contacts a provider that owns a resource in the plan.

## Inventory

`oilscope.platform.oilscope` reads the same project configuration, works out
which clouds it declares, and delegates to the upstream plugin of each one. The
inventory file is the whole configuration:

```yaml
plugin: oilscope.platform.oilscope
project_config_path: /absolute/path/project-config.json
```

A cloud nothing targets is never contacted, so it needs no credentials.

Group names and composed variable names are identical whichever cloud a host
came from. GCP builds groups from instance labels and AWS from instance tags,
but a playbook targets `database` either way, and the `ui` role resolves its
peers through `internal_ip` either way. Every host also carries
`oilscope_cloud` and joins `cloud_gcp` or `cloud_aws`, which is how a role
picks a provider-specific path without a playbook having to say which cloud it
is running against.

## What differs in practice

**Egress.** The GCP stack reaches the internet from its private subnet through
Cloud NAT. The AWS module uses a NAT gateway, which is billed per hour from the
moment it exists and is **not covered by the free tier** - roughly $33 a month
before any traffic. Destroy an AWS environment you are not using.

**Where a public VM sits.** In AWS the route to the internet belongs to the
subnet, so an Elastic IP on an instance in the NAT-routed subnet accepts no
inbound traffic - `apply` succeeds and the host is simply unreachable. GCP has
no such coupling: an external address works wherever the instance is. So a VM
that asks for a public IP is placed in the management subnet on AWS and left
where its role puts it on GCP. Both module calls pass the same expression; the
rule lives in `locals.tf`, and `validation.tf` rejects an `internal_ip` that
falls outside the subnet the VM ends up in - or, on AWS, on one of the four
addresses AWS reserves at the start of every subnet.

**SSH accounts.** Compute Engine takes public keys through instance metadata.
EC2 has no equivalent channel, so the AWS module writes a minimal cloud-init
document that creates the accounts and installs the keys, and nothing else.
Docker and the application remain Ansible's job in both clouds.

**Reading secrets.** Both clouds grant a workload access to its own secrets and
nothing more, and in both the VM proves its identity to the metadata service
rather than holding a key file. The mechanism differs: GCP's metadata server
returns a bearer token that works directly against the Secret Manager API,
while Secrets Manager requires a SigV4 signature on every request, so the AWS
path signs through the AWS CLI using the instance profile.

**Writing secret values.** The `secret_versions` role runs on the controller,
not on a VM, so it takes the cloud from the configuration rather than from a
host fact: a container is written wherever the workloads that read it live. The
payload reaches `gcloud` through `--data-file=-` and the AWS CLI through
`--secret-string file:///dev/stdin`, so in neither case does a value become a
command argument. Every value is checked before the first write, so a run
either updates the whole catalog or changes nothing.

**Enabling services.** `apis.tf` exists only for GCP. AWS services are
available to an account without being enabled per project.

**State.** The backend stays GCS for both. A bucket is a bucket, and one state
store for every environment is simpler than one per cloud; the AWS deployment
uses its own prefix.
