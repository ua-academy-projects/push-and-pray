locals {
  # Every instance that runs the agents: the workloads and the bastion. The
  # bastion's identity is count-based, so it joins only when the cloud is active.
  agent_roles = merge(
    { for name in keys(local.workload_vms) : name => module.identity[name].role_name },
    local.is_active ? { bastion = module.bastion_identity[0].role_name } : {},
  )
}

# One group for the whole environment; Fluent Bit names a stream per host.
# Host journals hold nothing that warrants a customer-managed key.
#trivy:ignore:AVD-AWS-0017
resource "aws_cloudwatch_log_group" "journald" {
  count = local.is_active ? 1 : 0

  name              = "/${local.resource_prefix}/journald"
  retention_in_days = 30
  tags              = local.common_tags
}

# Counterpart of roles/logging.logWriter: streams and events into the one
# group this environment owns, nothing else.
resource "aws_iam_role_policy" "log_writer" {
  for_each = local.agent_roles

  name = "${local.resource_prefix}-${each.key}-log-writer"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.journald[0].arn}:*"
    }]
  })
}

# Counterpart of roles/monitoring.metricWriter. Metrics have no ARN, so the
# namespace condition is what keeps this narrow.
resource "aws_iam_role_policy" "metric_writer" {
  for_each = local.agent_roles

  name = "${local.resource_prefix}-${each.key}-metric-writer"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["cloudwatch:PutMetricData"]
      Resource  = "*"
      Condition = { StringEquals = { "cloudwatch:namespace" = "CWAgent" } }
    }]
  })
}
