resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_ids

  name                    = "${var.config.name_prefix}/${var.config.environment}/${each.value}"
  description             = "OilScope ${each.value} secret container"
  recovery_window_in_days = 0
  tags                    = merge(local.common_tags, { secret_id = each.value })
}

resource "random_password" "generated" {
  for_each = toset(var.generated_secret_ids)

  length  = 32
  special = false

  lifecycle {
    precondition {
      condition     = contains(local.secret_ids, each.key)
      error_message = "Every generated secret ID must exist in a workload secret mapping."
    }
  }
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each = toset(var.generated_secret_ids)

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = random_password.generated[each.key].result
}
