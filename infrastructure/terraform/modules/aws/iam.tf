data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vm" {
  for_each = local.vms

  name               = "${local.resource_prefix}-${each.key}-runtime"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = each.value.tags
}

resource "aws_iam_instance_profile" "vm" {
  for_each = local.vms

  name = "${local.resource_prefix}-${each.key}-runtime"
  role = aws_iam_role.vm[each.key].name

  tags = each.value.tags
}

data "aws_iam_policy_document" "secret_access" {
  for_each = local.vms_with_secrets

  statement {
    sid    = "ReadAssignedSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      for secret_id in sort(tolist(each.value)) :
      aws_secretsmanager_secret.this[secret_id].arn
    ]
  }
}

resource "aws_iam_role_policy" "secret_access" {
  for_each = local.vms_with_secrets

  name   = "${local.resource_prefix}-${each.key}-secrets"
  role   = aws_iam_role.vm[each.key].name
  policy = data.aws_iam_policy_document.secret_access[each.key].json
}