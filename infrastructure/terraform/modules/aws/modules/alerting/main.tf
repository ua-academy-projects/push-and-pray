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

# The docker-events unit on every host writes one JSON line per container
# exit; an exit code other than zero is a crash, a planned stop is zero. The
# host's own name rides along as "instance", added by Fluent Bit.
resource "aws_cloudwatch_log_metric_filter" "container_died" {
  for_each = {
    for pair in flatten([
      for instance in values(var.instances) : [
        for container in lookup(var.containers_by_role, instance.role, []) :
        { instance = instance.name, container = container }
      ]
    ]) : "${pair.instance}/${pair.container}" => pair
  }

  name           = "${var.resource_prefix}-${each.value.container}-died"
  log_group_name = var.log_group_name
  pattern        = "{ ($._SYSTEMD_UNIT = \"docker-events.service\") && ($.instance = \"${each.value.instance}\") && ($.Actor.Attributes.name = \"${each.value.container}\") && ($.Actor.Attributes.exitCode != \"0\") }"

  metric_transformation {
    name       = "ContainerDied"
    namespace  = "${var.resource_prefix}/docker"
    value      = "1"
    dimensions = { instance = "$.instance", container = "$.Actor.Attributes.name" }
  }
}

resource "aws_cloudwatch_metric_alarm" "container_died" {
  for_each = aws_cloudwatch_log_metric_filter.container_died

  alarm_name          = "${var.resource_prefix}-${split("/", each.key)[1]}-died"
  alarm_description   = "Container ${split("/", each.key)[1]} on instance ${split("/", each.key)[0]} exited with a non-zero code"
  namespace           = each.value.metric_transformation[0].namespace
  metric_name         = each.value.metric_transformation[0].name
  dimensions          = { instance = split("/", each.key)[0], container = split("/", each.key)[1] }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  for_each = { for name, instance in var.instances : instance.role => instance if contains(["ui", "history", "fetcher"], instance.role) }

  name           = "${var.resource_prefix}-${each.key}-5xx"
  log_group_name = var.log_group_name
  pattern        = "{ ($.CONTAINER_NAME = \"petroscope-${each.key}-1\") && ($.status >= 500) }"

  metric_transformation {
    name       = "Http5xx"
    namespace  = "${var.resource_prefix}/http"
    value      = "1"
    dimensions = { service = "$.CONTAINER_NAME" }
  }
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  for_each = aws_cloudwatch_log_metric_filter.http_5xx

  alarm_name          = "${var.resource_prefix}-${each.key}-5xx"
  alarm_description   = "petroscope-${each.key}-1 on instance ${each.value.name} answered with a 5xx status"
  namespace           = each.value.metric_transformation[0].namespace
  metric_name         = each.value.metric_transformation[0].name
  dimensions          = { service = "petroscope-${each.key}-1" }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
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
