# Additive publisher permissions; installation remains in VM deployment.
locals {
  monitoring_enabled         = try(var.config.monitoring.enabled, true)
  monitoring_metrics_enabled = local.monitoring_enabled && try(var.config.monitoring.agent_metrics_enabled, false)
  monitoring_logs_enabled    = local.monitoring_enabled && try(var.config.monitoring.logs_enabled, true)
  application_logs_enabled   = local.monitoring_enabled && (try(var.config.monitoring.application_metrics_enabled, false) || try(var.config.monitoring.service_logs_enabled, false))
  monitoring_log_group       = "/${var.config.name_prefix}/${var.config.environment}/traefik"
  monitoring_vms = {
    for name, vm in local.aws_vms : name => vm
    if vm.role != "bastion" && (local.application_logs_enabled || local.monitoring_metrics_enabled || (local.monitoring_logs_enabled && vm.role == "ui"))
  }
}
data "aws_partition" "monitoring" {
  count = length(local.monitoring_vms) > 0 ? 1 : 0
}
data "aws_caller_identity" "monitoring" {
  count = length(local.monitoring_vms) > 0 ? 1 : 0
}
resource "aws_iam_role_policy" "monitoring" {
  for_each = local.monitoring_vms
  name     = "${local.resource_prefix}-${each.key}-monitoring"
  role     = aws_iam_role.ec2_role[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.monitoring_metrics_enabled ? [{
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "CWAgent" } }
      }] : [],
      local.monitoring_logs_enabled && each.value.role == "ui" ? [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:${data.aws_partition.monitoring[0].partition}:logs:${var.config.region_map[var.config.region].aws.region}:${data.aws_caller_identity.monitoring[0].account_id}:log-group:${local.monitoring_log_group}:*"
      }] : [],
      local.application_logs_enabled ? [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:${data.aws_partition.monitoring[0].partition}:logs:${var.config.region_map[var.config.region].aws.region}:${data.aws_caller_identity.monitoring[0].account_id}:log-group:/${var.config.name_prefix}/${var.config.environment}/application:*"
      }] : []
    )
  })
}
