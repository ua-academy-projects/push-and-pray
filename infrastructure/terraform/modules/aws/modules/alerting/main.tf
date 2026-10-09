# CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed
# SNS key, and an alarm subject line does not warrant a customer-managed one.
#trivy:ignore:AVD-AWS-0095
resource "aws_sns_topic" "alerts" {
  name = "${var.resource_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}

# One alarm per instance and watched metric. The health check treats missing
# data as breaching, so a stopped instance - which reports nothing - alarms.
resource "aws_cloudwatch_metric_alarm" "metric" {
  for_each = {
    for pair in setproduct(keys(var.instances), keys(var.metrics)) :
    "${pair[0]}/${pair[1]}" => { instance = var.instances[pair[0]], metric = var.metrics[pair[1]] }
  }

  alarm_name          = "${var.resource_prefix}-${each.value.instance.name}-${split("/", each.key)[1]}"
  alarm_description   = "${each.value.instance.name}: ${each.value.metric.title} ${each.value.metric.comparison} ${each.value.metric.threshold}"
  namespace           = each.value.metric.namespace
  metric_name         = each.value.metric.name
  statistic           = each.value.metric.stat
  period              = 60
  evaluation_periods  = 5
  threshold           = each.value.metric.threshold
  comparison_operator = each.value.metric.comparison
  treat_missing_data  = each.value.metric.missing
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    (each.value.metric.dimension) = each.value.metric.dimension == "VolumeId" ? each.value.instance.volume_id : each.value.instance.id
  }
}

# Budgets mail the address directly; no topic in between.
resource "aws_budgets_budget" "monthly" {
  count = var.budget_usd != null ? 1 : 0

  name         = "${var.resource_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  tags         = var.tags

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email]
  }
}
