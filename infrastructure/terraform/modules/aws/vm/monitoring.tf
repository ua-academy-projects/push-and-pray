locals {
  monitoring_enabled         = try(var.config.monitoring.enabled, true)
  monitoring_metrics_enabled = local.monitoring_enabled && try(var.config.monitoring.agent_metrics_enabled, false)
  monitoring_logs_enabled    = local.monitoring_enabled && try(var.config.monitoring.logs_enabled, true)
  application_logs_enabled   = local.monitoring_enabled && (try(var.config.monitoring.application_metrics_enabled, false) || try(var.config.monitoring.service_logs_enabled, false))

  monitoring_policy_enabled = length(local.aws_vms) > 0 && (
    local.monitoring_metrics_enabled || local.monitoring_logs_enabled || local.application_logs_enabled
  )
}

data "aws_partition" "monitoring" {
  count = local.monitoring_policy_enabled ? 1 : 0
}

data "aws_caller_identity" "monitoring" {
  count = local.monitoring_policy_enabled ? 1 : 0
}

resource "aws_iam_role_policy" "monitoring" {
  count = local.monitoring_policy_enabled ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-node-monitoring"
  role = aws_iam_role.node[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.monitoring_metrics_enabled ? [{
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = [
          "CWAgent",
          "${var.config.name_prefix}-${var.config.environment}/Cluster",
        ] } }
      }] : [],
      local.monitoring_logs_enabled ? [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:${data.aws_partition.monitoring[0].partition}:logs:${var.config.region_map[var.config.region].aws.region}:${data.aws_caller_identity.monitoring[0].account_id}:log-group:/${var.config.name_prefix}/${var.config.environment}/traefik:*"
      }] : [],
      local.application_logs_enabled ? [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:${data.aws_partition.monitoring[0].partition}:logs:${var.config.region_map[var.config.region].aws.region}:${data.aws_caller_identity.monitoring[0].account_id}:log-group:/${var.config.name_prefix}/${var.config.environment}/application:*"
      }] : []
    )
  })
}
