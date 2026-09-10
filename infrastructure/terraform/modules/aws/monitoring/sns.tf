resource "aws_sns_topic" "alerts" {
    count = var.has_selected_vms ? 1 : 0

    name = "${local.resource_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
    count = var.has_selected_vms ? 1 : 0

    topic_arn = aws_sns_topic.alerts[0].arn
    protocol  = "email"
    endpoint  = var.config.monitoring.notification_email
}