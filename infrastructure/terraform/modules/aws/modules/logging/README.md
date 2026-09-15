# AWS logging module

Creates the log group the journals land in and lets every instance role
write to it. The agent that does the sending is installed by the Ansible role
`observability_agent`; this module only opens the door.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_cloudwatch_log_group` | `/<prefix>/journald`, one stream per host, retention set |
| `aws_iam_role_policy` | Per role: create streams and put events into that group only |

The GCP counterpart grants the writer on the project; here the group is
named in the policy. Same least privilege reached from the other end.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for the group and policy names |
| `identities` | IAM role name per instance name, the bastion included |
| `retention_days` | Days an entry is kept; defaults to 30 |
| `tags` | Tags for the group |

## Outputs

| Name | Description |
| --- | --- |
| `log_group_name` | The group's name, which alert filters read |
| `log_group_arn` | Its ARN |

## Usage

```hcl
module "logging" {
  source = "./modules/logging"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  identities      = local.identities
  tags            = local.common_tags
}
```

## License

GPL-2.0-or-later
