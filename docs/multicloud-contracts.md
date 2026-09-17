# OilScope multi-cloud contracts

Status: implemented contract; local static/unit validation completed, real
provider plans and live acceptance pending.

## Configuration identity

Every project configuration has these top-level selectors:

```json
{
  "schema_version": 1,
  "cloud_provider": "aws",
  "data_profile": "portable",
  "deployment_runtime": "compose"
}
```

Rules:

- `schema_version` must be exactly a version supported by the repository.
- `cloud_provider` is `aws` or `gcp` and selects one isolated Terraform root.
- `data_profile` is `portable` or `managed`.
- only `compose` is implemented; `k3s` is reserved and rejected with a clear
  error.
- a VM may carry an optional `provider` for forward compatibility, but it must
  equal `cloud_provider` in schema version 1.

During migration, old configurations are normalised as follows:

| Legacy field | Version 1 meaning |
| --- | --- |
| `default_cloud` | `cloud_provider` |
| `manage_db=false` | `data_profile=portable` |
| `manage_db=true` | `data_profile=managed` |
| missing runtime | `deployment_runtime=compose` |
| VM `cloud` | deprecated alias of VM `provider` |

Supplying both old and new fields with conflicting values is an error. Current
examples temporarily carry matching legacy aliases for consumers outside the
live version 1 wrapper; new logic uses the versioned fields.

## Provider settings

Provider account and location settings stay in provider-specific sections and
never contain credentials:

```json
{
  "clouds": {
    "aws": {
      "locations": {
        "primary": {"region": "eu-west-1", "zone": "eu-west-1a"}
      }
    },
    "gcp": {
      "project_id": "example-project",
      "locations": {
        "primary": {"region": "europe-west1", "zone": "europe-west1-b"}
      }
    }
  }
}
```

Credentials and local CLI profile names are deliberately absent. Terraform and
CI use standard AWS/GCP credential chains and short-lived
assumed/impersonated identities.

## Logical infrastructure inputs

Common inputs express intent:

- compute class: `micro`, `small`;
- disk class: `standard`, `balanced`, `ssd`;
- image: `ubuntu-lts`;
- architecture: `amd64` or `arm64`;
- access profile: `bastion`, `ui`, `history`, `fetcher`, `infra`;
- secret references by logical environment-variable name;
- static public address as a boolean capability, not a provider resource name.

Provider modules map these values to GCE/EC2, PD/EBS, image family/AMI, firewall
tags/security groups, addresses/EIPs, and provider secret identifiers. Provider
overrides are optional escape hatches and are never the primary interface.

## Node output contract

Each provider returns a map keyed by stable logical node name:

```hcl
object({
  contract_version = number
  name             = string
  role             = string
  provider         = string
  region           = string
  zone             = string
  architecture     = string
  private_address  = string
  public_address   = optional(string)
  ssh = object({
    user             = string
    port             = number
    proxyjump_node   = optional(string)
    host_key_alias   = optional(string)
  })
  disks            = list(object({ id = string, purpose = string }))
  runtime_identity = string
  access_profiles  = set(string)
  labels           = map(string)
})
```

The contract contains no private key, password, token, provider credential, or
secret value.

## Deployment output contract

Both isolated roots expose one `deployment` object:

```hcl
object({
  contract_version = number
  schema_version   = number
  deployment_name = string
  environment     = string
  provider        = string
  data_profile    = string
  runtime         = string
  nodes           = map(any)
  bastion         = optional(any)
  ui = object({
    hostname       = string
    public_address = string
    url            = string
  })
  database = object({
    mode      = string
    engine    = string
    host      = string
    port      = number
    name      = string
    username  = string
    secret_id = string
  })
  registry = object({
    provider       = string
    host           = string
    immutable_tags = bool
    repositories   = map(any)
    images          = map(string)
  })
  monitoring = object({
    dashboard_id       = optional(string)
    alert_policy_ids   = list(string)
    availability_id    = optional(string)
    log_metric_ids     = list(string)
  })
})
```

Legacy Terraform outputs remain as projections during migration. The live
deployment wrapper accepts only schema version 1 so it cannot partially apply
the unsupported mixed contract.

## Application environment contract

Applications are provider-neutral:

| Setting | Portable | Managed |
| --- | --- | --- |
| `DATABASE_URL` | Private PostgreSQL VM | Private RDS/Cloud SQL |
| `QUEUE_BACKEND` | `postgres` | `rabbitmq` |
| RabbitMQ settings | Absent | Required |
| `SESSION_BACKEND` | `postgres` | `redis` |
| `REDIS_URL` | Absent | Required |
| `SESSION_COOKIE_SECURE` | `true` for public HTTPS | `true` for public HTTPS |

Applications must not receive `cloud_provider` and must not branch on AWS/GCP.

## Inventory contract

Ansible consumes only the normalized `deployment` output and groups nodes by
`role`. For private nodes it constructs ProxyJump from the bastion object. The
inventory contains secret identifiers but never resolved values. Secret values
are fetched on the target or controller only for the task that needs them and
are protected with `no_log`.

## State identity contract

Foundation bootstrap generates backend configuration under the ignored path:

```text
.generated/<environment>/<provider>/<deployment>/
├── foundation.json
└── backend.hcl
```

The remote state identity is:

```text
<environment>/<provider>/<deployment>/terraform.tfstate
```

The backend type is selected by the isolated root/wrapper before
`terraform init`; it is never selected by a Terraform input variable.

## Foundation ownership

Bootstrap owns only resources required before Terraform can initialise:

- remote-state bucket and locking mechanism;
- Terraform, CI, and runtime identity foundations;
- required trust/OIDC or impersonation bindings;
- GCP project/API enablement when explicitly requested.

Main Terraform owns workload networking, VMs, databases, application secret
containers, registries, DNS, and monitoring. One resource must never be managed
by both layers.

## Validation states

Documentation and reports use exactly these levels:

- `implemented`: code exists but has not necessarily passed validation;
- `statically validated`: formatting, schema, unit/static tests and provider
  plans passed without changing cloud state;
- `live infrastructure validated`: authorised apply and cloud resource checks
  passed;
- `application accepted`: containers, migrations, queue flow, sessions, HTTPS,
  logs, alerts, and external port restrictions passed end to end.

Passing Terraform validation or apply alone is never application acceptance.
