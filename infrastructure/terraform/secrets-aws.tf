locals {
  aws_all_secret_ids = distinct(flatten([
    for vm in values(local.aws_vms) : values(vm.secret_mappings)
  ]))

  aws_vms_with_secrets = {
    for name, vm in local.aws_vms : name => distinct(values(vm.secret_mappings))
    if length(vm.secret_mappings) > 0
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.aws_all_secret_ids)
  name     = each.value
  tags     = local.common_labels
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = local.aws_vms_with_secrets

  name = "${each.key}-secret-access"
  role = module.aws_vms[each.key].role_name

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
