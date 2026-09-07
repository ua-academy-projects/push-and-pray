resource "aws_iam_role" "roles" {
  for_each = local.roles

  name = "${local.resource_prefix}-${each.key}-runtime"
  tags = local.tags[each.key]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "profiles" {
  for_each = local.roles

  name = "${local.resource_prefix}-${each.key}-runtime"
  role = aws_iam_role.roles[each.key].name
  tags = local.tags[each.key]
}

resource "aws_secretsmanager_secret" "secrets" {
  for_each = local.secret_ids

  name = each.value
  tags = var.config.common_labels
}

resource "aws_iam_role_policy" "readers" {
  for_each = local.secret_readers

  name = "${local.resource_prefix}-${each.key}-secrets"
  role = aws_iam_role.roles[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = [
        for secret_id in sort(tolist(each.value)) :
        aws_secretsmanager_secret.secrets[secret_id].arn
      ]
    }]
  })
}
