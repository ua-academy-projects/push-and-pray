output "summary" {
  description = "Identifiers useful for opening or integrating the AWS monitoring resources."
  value = {
    dashboard_name             = aws_cloudwatch_dashboard.overview.dashboard_name
    alarm_topic_arn            = aws_sns_topic.alarms.arn
    cpu_alarm_arns             = { for name, alarm in aws_cloudwatch_metric_alarm.high_cpu : name => alarm.arn }
    disk_alarm_arns            = { for name, alarm in aws_cloudwatch_metric_alarm.high_disk : name => alarm.arn }
    status_alarm_arns          = { for name, alarm in aws_cloudwatch_metric_alarm.instance_status_failed : name => alarm.arn }
    rds_cpu_alarm_arn          = try(aws_cloudwatch_metric_alarm.rds_high_cpu[0].arn, null)
    rds_storage_alarm_arn      = try(aws_cloudwatch_metric_alarm.rds_low_free_storage[0].arn, null)
    log_group_name             = try(aws_cloudwatch_log_group.docker[0].name, null)
    log_alarm_arn              = try(aws_cloudwatch_metric_alarm.container_errors[0].arn, null)
    uptime_check_id            = try(aws_route53_health_check.ui[0].id, null)
    uptime_alarm_arn           = try(aws_cloudwatch_metric_alarm.ui_unavailable[0].arn, null)
    budget_id                  = try(aws_budgets_budget.monthly[0].id, null)
    email_confirmation_pending = true
  }
}
