resource "aws_cloudwatch_log_group" "journald" {
  name              = local.log_group_name
  retention_in_days = var.config.monitoring.log_retention_days

  tags = merge(var.config.common_labels, {
    environment = var.config.environment
    managed_by  = "terraform"
  })
}

resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/oilscope/${var.config.environment}/prometheus"
  retention_in_days = var.config.monitoring.log_retention_days

  tags = merge(var.config.common_labels, {
    environment = var.config.environment
    managed_by  = "terraform"
  })
}

resource "aws_iam_role_policy" "monitoring" {
  for_each = var.role_names

  name = "${local.resource_prefix}-${each.key}-monitoring"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = local.namespace
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ]
        Resource = [
          "${aws_cloudwatch_log_group.journald.arn}:*",
          "${aws_cloudwatch_log_group.prometheus.arn}:*",
        ]
      },
    ]
  })
}
