locals {
  all_secret_ids = distinct(flatten(values(var.workload_secret_access)))
  workloads_with_secrets = {
    for name, secret_ids in var.workload_secret_access : name => secret_ids
    if length(secret_ids) > 0
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.all_secret_ids)

  name = each.value
  tags = var.tags
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
