locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  workload_secret_access = {
    for name, vm in local.vms : name => distinct(values(vm.secret_mappings))
    if vm.role != "bastion"
  }

  location       = try(var.config.locations[one(distinct([for vm in values(local.vms) : vm.location]))].aws, null)
  all_secret_ids = distinct(flatten(values(local.workload_secret_access)))
  workloads_with_secrets = {
    for name, secret_ids in local.workload_secret_access : name => secret_ids
    if length(secret_ids) > 0
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.all_secret_ids)

  region = local.location.region
  name   = each.value
  tags   = var.config.common_labels
}

data "aws_iam_policy_document" "workload_access" {
  for_each = local.workloads_with_secrets

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      for secret_id in each.value :
      aws_secretsmanager_secret.this[secret_id].arn
    ]
  }
}

resource "aws_iam_role_policy" "workload_access" {
  for_each = local.workloads_with_secrets

  name   = "${each.key}-secret-access"
  role   = var.iam_role_names[each.key]
  policy = data.aws_iam_policy_document.workload_access[each.key].json
}
