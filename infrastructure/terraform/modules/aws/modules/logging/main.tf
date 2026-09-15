# One group for the whole environment; Fluent Bit names a stream per host.
# Host journals hold nothing that warrants a customer-managed key.
#trivy:ignore:AVD-AWS-0017
resource "aws_cloudwatch_log_group" "journald" {
  name              = "/${var.resource_prefix}/journald"
  retention_in_days = var.retention_days
  tags              = var.tags
}

# Counterpart of roles/logging.logWriter: streams and events into the one
# group this environment owns, nothing else.
resource "aws_iam_role_policy" "log_writer" {
  for_each = var.identities

  name = "${var.resource_prefix}-${each.key}-log-writer"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.journald.arn}:*"
    }]
  })
}
