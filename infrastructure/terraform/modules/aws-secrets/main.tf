resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  region = each.value.region
  name   = each.value.secret_id
  tags   = local.context.labels
}

resource "aws_iam_role" "vm" {
  for_each = local.vms

  name = "${local.context.resource_prefix}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.context.labels
}

resource "aws_iam_role_policy" "secret_access" {
  for_each = {
    for name, vm in local.vms : name => vm
    if length(vm.secret_mappings) > 0
  }

  name = "secret-access"
  role = aws_iam_role.vm[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
      ]
      Resource = [
        for secret_id in distinct(values(each.value.secret_mappings)) :
        aws_secretsmanager_secret.this["${each.value.region}/${secret_id}"].arn
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "vm" {
  for_each = local.vms

  name = "${local.context.resource_prefix}-${each.key}"
  role = aws_iam_role.vm[each.key].name
  tags = local.context.labels
}
