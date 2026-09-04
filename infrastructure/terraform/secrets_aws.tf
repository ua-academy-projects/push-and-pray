locals {
  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  aws_workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion" && coalesce(try(vm.cloud, null), local.config.cloud) == "aws"
  }

  all_aws_secret_ids = distinct(flatten([
    for workload in values(local.aws_workload_vms) : values(workload.secret_mappings)
  ]))
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.all_aws_secret_ids)
  name     = "${local.resource_prefix}-${each.value}"
}

resource "aws_secretsmanager_secret_policy" "version_adder" {
  for_each = length(var.aws_secret_version_managers) > 0 ? aws_secretsmanager_secret.this : {}

  secret_arn = each.value.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.aws_secret_version_managers }
      Action    = "secretsmanager:PutSecretValue"
      Resource  = "*"
    }]
  })
}

resource "aws_iam_role_policy" "secret_access" {
  for_each = local.aws_workload_vms

  name = "${local.resource_prefix}-${each.key}-secrets"
  role = module.aws_vm.iam_role_names[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        for secret_id in distinct(values(each.value.secret_mappings)) :
        aws_secretsmanager_secret.this[secret_id].arn
      ]
    }]
  })
}
