resource "aws_sns_topic" "alerts" {
  count = local.notifications_enabled ? 1 : 0
  name  = "${local.resource_prefix}-monitoring"
  tags  = local.common_labels
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = local.recipients
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}
