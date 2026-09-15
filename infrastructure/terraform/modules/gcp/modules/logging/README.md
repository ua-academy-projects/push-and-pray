# GCP logging module

Lets every VM identity write to Cloud Logging and sets how long the project
keeps what they send. The agent that does the sending is installed by the
Ansible role `observability_agent`; this module only opens the door.

## Resources

| Resource | Purpose |
| --- | --- |
| `google_project_iam_member` | `roles/logging.logWriter` for each identity |
| `google_logging_project_bucket_config` | Retention of the `_Default` bucket, where the journals land |

The `_Default` bucket exists in every project and cannot be deleted; the
resource manages its retention and leaves the bucket behind on destroy.

## Inputs

| Name | Description |
| --- | --- |
| `project_id` | Project whose IAM and log bucket are managed |
| `identities` | IAM member string per VM name, the bastion included |
| `retention_days` | Days an entry is kept; defaults to 30 |

## Outputs

| Name | Description |
| --- | --- |
| `log_name` | `projects/<id>/logs/journald` - the log the Ops Agent writes, which alert filters start from |

## Usage

```hcl
module "logging" {
  source = "./modules/logging"
  count  = local.is_active ? 1 : 0

  project_id = local.profile.project_id
  identities = local.identities
}
```

## License

GPL-2.0-or-later
