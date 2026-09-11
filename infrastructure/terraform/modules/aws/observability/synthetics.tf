data "archive_file" "canary" {
  type        = "zip"
  output_path = "${path.root}/.terraform/${var.resource_prefix}-canary.zip"

  source {
    filename = "nodejs/node_modules/oilscope-canary.js"
    content  = <<-JS
      const synthetics = require('Synthetics');

      const validate = async (response) => {
        if (response.statusCode !== 200) {
          throw new Error(`Expected HTTP 200, received $${response.statusCode}`);
        }
      };

      exports.handler = async () => {
        const base = new URL(process.env.TARGET_URL);
        for (const [stepName, path] of [['GET health', '/health'], ['GET api-latest', '/api/latest']]) {
          await synthetics.executeHttpStep(
            stepName,
            {
              protocol: base.protocol,
              hostname: base.hostname,
              port: base.port || 443,
              path,
              method: 'GET',
              headers: { 'User-Agent': 'oilscope-cloudwatch-synthetic' },
            },
            validate,
          );
        }
      };
    JS
  }
}

resource "aws_s3_bucket" "synthetics" {
  bucket        = "${var.resource_prefix}-synthetics-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "synthetics" {
  bucket = aws_s3_bucket.synthetics.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "synthetics" {
  bucket = aws_s3_bucket.synthetics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "synthetics" {
  name = "${var.resource_prefix}-synthetics"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "synthetics" {
  name = "${var.resource_prefix}-synthetics"
  role = aws_iam_role.synthetics.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.synthetics.arn,
          "${aws_s3_bucket.synthetics.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "CloudWatchSynthetics" }
        }
      },
    ]
  })
}

resource "aws_synthetics_canary" "api" {
  name                     = "${var.resource_prefix}-api"
  artifact_s3_location     = "s3://${aws_s3_bucket.synthetics.id}/artifacts/"
  execution_role_arn       = aws_iam_role.synthetics.arn
  handler                  = "oilscope-canary.handler"
  runtime_version          = "syn-nodejs-puppeteer-17.0"
  zip_file                 = data.archive_file.canary.output_path
  start_canary             = true
  success_retention_period = 14
  failure_retention_period = 30
  tags                     = var.tags

  schedule {
    expression          = "rate(5 minutes)"
    duration_in_seconds = 0
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 960
    environment_variables = {
      TARGET_URL = var.synthetic_url
    }
  }

  depends_on = [
    aws_iam_role_policy.synthetics,
    aws_s3_bucket_public_access_block.synthetics,
    aws_s3_bucket_server_side_encryption_configuration.synthetics,
  ]
}

resource "aws_cloudwatch_metric_alarm" "synthetic_failed" {
  alarm_name          = "${var.resource_prefix}-aws-synthetic-failed"
  alarm_description   = "Kickoff: synthetic /health or /api/latest check failed twice. Closure: synthetic checks recovered. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 100
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { CanaryName = aws_synthetics_canary.api.name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}
