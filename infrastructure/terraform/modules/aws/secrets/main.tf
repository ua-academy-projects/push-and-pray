resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.enabled ? flatten([
    for workload in values(var.config.secret_mappings) : values(workload)
  ]) : [])
  name = each.value
  tags = local.common_labels
}
