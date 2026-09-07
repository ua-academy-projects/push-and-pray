# GCP identity module

Creates the runtime identity of one VM: a dedicated service account, and
nothing else.

Separate from the [VM module](../vm/README.md) on two of the three counts the
Terraform module guidance names:

- **Privileges** - a service account is an IAM object. Keeping it inside a
  compute module meant `secrets.tf` had to reach into that module to write a
  binding, crossing a boundary it has no business crossing.
- **Volatility** - the identity outlives the instance. A VM is replaced
  whenever its image, size or address changes; its identity should not be, and
  the secret bindings that point at it should not have to be rewritten.

Encapsulation argues the other way - the two are always deployed together - so
this split is about who owns what, not about what ships when.

## Resources

| Resource | Purpose |
| --- | --- |
| `google_service_account` | Identity the instance runs as; secret bindings attach to it |

## Inputs

| Name | Description |
| --- | --- |
| `name` | Name for the service account, matching the VM it belongs to |
| `description` | What the identity is for; a sensible default is derived from the name |

`name` must satisfy GCP's account-id rules: 6 to 30 characters, lowercase.

## Outputs

| Name | Description |
| --- | --- |
| `identity` | The service-account email - the GCP counterpart of an AWS role ARN |
| `member` | The same as an IAM member string, ready for a binding |
| `email`, `name`, `id` | Address and resource identifiers |
| `unique_id` | Numeric ID that survives a rename |
| `account_id` | Short ID, the part before the `@` |

`member` exists so that callers stop building `"serviceAccount:${...}"` by
hand; `identity` is named to match the AWS module, which returns an ARN there.

## Usage

```hcl
module "identity" {
  source   = "./modules/identity"
  for_each = local.my_vms

  name        = "${local.resource_prefix}-${each.key}"
  description = "Runtime identity for the ${each.value.role} workload"
}
```

The VM module then takes `module.identity[each.key].email`, and `secrets.tf`
binds `module.identity[...].member` without touching compute at all.

## License

GPL-2.0-or-later
