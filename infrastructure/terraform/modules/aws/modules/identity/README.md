# AWS identity module

Creates the runtime identity of one instance: an IAM role and the instance
profile that carries it, and nothing else.

Separate from the [VM module](../vm/README.md) on two of the three counts the
Terraform module guidance names:

- **Privileges** - a role and its policies are IAM objects. Keeping them inside
  a compute module meant `secrets.tf` had to reach into that module to attach a
  policy, crossing a boundary it has no business crossing.
- **Volatility** - the identity outlives the instance. A VM is replaced
  whenever its AMI, type or address changes; its role should not be, and the
  policies attached to it should not have to be rewritten.

Encapsulation argues the other way - the two are always deployed together - so
this split is about who owns what, not about what ships when.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_iam_role` | Identity the instance assumes; secret policies attach to it |
| `aws_iam_instance_profile` | The carrier - AWS cannot attach a role to an instance directly |

The trust policy allows `ec2.amazonaws.com` to assume the role and nothing
else.

## Inputs

| Name | Description |
| --- | --- |
| `name` | Name for the role and its instance profile, matching the VM |
| `description` | What the identity is for; a sensible default is derived from the name |
| `tags` | Tags for both resources |

## Outputs

| Name | Description |
| --- | --- |
| `identity` | The role ARN - the AWS counterpart of a GCP service-account email |
| `member` | The same, as a policy principal; on AWS this is the ARN itself |
| `role_name` | For attaching inline policies |
| `role_arn`, `role_unique_id` | ARN and a rename-proof ID |
| `instance_profile_name` | What an EC2 instance actually takes |
| `instance_profile_arn`, `instance_profile_unique_id` | The profile's identifiers |

## Usage

```hcl
module "identity" {
  source   = "./modules/identity"
  for_each = local.my_vms

  name        = "${local.resource_prefix}-${each.key}"
  description = "Runtime identity for the ${each.value.role} workload"
  tags        = local.common_tags
}
```

The VM module then takes `module.identity[each.key].instance_profile_name`, and
`secrets.tf` attaches policies to `module.identity[...].role_name` without
touching compute at all.

## Known wrinkle

A freshly created instance profile can take a moment to propagate, so an
instance created in the same apply occasionally fails with `Invalid IAM
Instance Profile name`. Re-running `apply` resolves it. This predates the split
and is a property of AWS, not of the module layout.

## License

GPL-2.0-or-later
