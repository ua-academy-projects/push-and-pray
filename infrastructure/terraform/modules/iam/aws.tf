resource "aws_iam_role" "ec2" {
  count = length(local.aws_vms) > 0 ? 1 : 0
  name  = "${local.resource_prefix}-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.aws_tags
}

resource "aws_iam_instance_profile" "ec2" {
  count = length(local.aws_vms) > 0 ? 1 : 0
  name  = "${local.resource_prefix}-ec2"
  role  = aws_iam_role.ec2[0].name
  tags  = local.aws_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = length(local.aws_vms) > 0 ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "secrets" {
  count = length(local.aws_vms) > 0 && var.enable_aws_secret_access ? 1 : 0

  name = "read-oilscope-secrets"
  role = aws_iam_role.ec2[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadOilScopeSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.aws_secret_arns
    }]
  })
}
