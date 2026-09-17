data "aws_partition" "current" {
  count = local.synthetics_enabled ? 1 : 0
}
data "aws_caller_identity" "current" {
  count = local.synthetics_enabled ? 1 : 0
}
data "archive_file" "health" {
  count       = local.synthetics_enabled ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/canary/health.js"
  output_path = "${path.root}/.terraform/${local.canary_name}-${filesha256("${path.module}/canary/health.js")}.zip"
}
resource "aws_s3_bucket" "canary" {
  count         = local.synthetics_enabled ? 1 : 0
  bucket_prefix = "${local.canary_name}-"
  # Preserve artifacts on accidental destruction. Empty the bucket explicitly first.
  force_destroy = false
  tags          = local.common_labels
}
resource "aws_s3_bucket_public_access_block" "canary" {
  count                   = local.synthetics_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.canary[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "canary" {
  count  = local.synthetics_enabled ? 1 : 0
  bucket = aws_s3_bucket.canary[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "canary" {
  count  = local.synthetics_enabled ? 1 : 0
  bucket = aws_s3_bucket.canary[0].id
  rule {
    id     = "expire-results"
    status = "Enabled"
    filter { prefix = "results/" }
    expiration { days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_iam_role" "canary" {
  count = local.synthetics_enabled ? 1 : 0
  name  = "${local.canary_name}-execution"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_labels
}
resource "aws_iam_role_policy" "canary" {
  count = local.synthetics_enabled ? 1 : 0
  name  = "${local.canary_name}-execution"
  role  = aws_iam_role.canary[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.canary[0].arn}/results/*" },
      { Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = aws_s3_bucket.canary[0].arn },
      {
        Effect   = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:PutRetentionPolicy"]
        Resource = "arn:${data.aws_partition.current[0].partition}:logs:${local.region}:${data.aws_caller_identity.current[0].account_id}:log-group:/aws/lambda/cwsyn-${local.canary_name}-*"
      },
      { Effect = "Allow", Action = "cloudwatch:PutMetricData", Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "CloudWatchSynthetics" } } }
    ]
  })
}
resource "aws_synthetics_canary" "health" {
  count                    = local.synthetics_enabled ? 1 : 0
  name                     = local.canary_name
  artifact_s3_location     = "s3://${aws_s3_bucket.canary[0].bucket}/results/"
  execution_role_arn       = aws_iam_role.canary[0].arn
  handler                  = "health.handler"
  runtime_version          = local.settings.synthetics.runtime_version
  zip_file                 = data.archive_file.health[0].output_path
  start_canary             = true
  delete_lambda            = true
  success_retention_period = 7
  failure_retention_period = 7
  schedule {
    expression = "rate(${local.settings.synthetics.period_minutes} ${local.settings.synthetics.period_minutes == 1 ? "minute" : "minutes"})"
  }
  run_config {
    timeout_in_seconds = local.settings.synthetics.browser_enabled ? 120 : 30
    active_tracing     = false
    environment_variables = {
      LOG_RETENTION_DAYS = tostring(local.settings.log_retention_days)
      BROWSER_ENABLED    = tostring(local.settings.synthetics.browser_enabled)
      HEALTH_URL         = "https://${local.settings.synthetics.hostname}${local.settings.synthetics.path}"
    }
  }
  tags       = local.common_labels
  depends_on = [aws_iam_role_policy.canary, aws_s3_bucket_public_access_block.canary, aws_s3_bucket_server_side_encryption_configuration.canary]
}
