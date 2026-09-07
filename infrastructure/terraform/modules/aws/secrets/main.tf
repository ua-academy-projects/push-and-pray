resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.all_secret_ids)
  name     = each.value
  tags     = local.common_labels
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = local.vms_with_secrets

  name = "${each.key}-secret-access"
  role = var.vms[each.key].role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [for secret_id in each.value : aws_secretsmanager_secret.this[secret_id].arn]
      }
    ]
  })
}
