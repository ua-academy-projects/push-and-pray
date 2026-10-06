resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.enabled ? concat(
    flatten([
      for workload in values(var.config.secret_mappings) : values(workload)
    ]),
    local.console_secret_ids
  ) : [])
  name                    = each.value
  recovery_window_in_days = 0
  tags                    = local.common_labels
}
