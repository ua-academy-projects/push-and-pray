output "destination" {
  description = "CloudWatch destination configured for the VM agents."
  value = {
    metrics_namespace = local.namespace
    log_group_name    = aws_cloudwatch_log_group.journald.name
    dashboard_name    = aws_cloudwatch_dashboard.main.dashboard_name
    alert_topic_arn   = aws_sns_topic.alerts.arn
  }
}
