output "summary" {
  description = "Identifiers useful for opening or integrating the AWS monitoring resources."
  value = {
    dashboard_name             = aws_cloudwatch_dashboard.overview.dashboard_name
    alarm_topic_arn            = aws_sns_topic.alarms.arn
    cpu_alarm_arns             = { for name, alarm in aws_cloudwatch_metric_alarm.high_cpu : name => alarm.arn }
    status_alarm_arns          = { for name, alarm in aws_cloudwatch_metric_alarm.instance_status_failed : name => alarm.arn }
    email_confirmation_pending = true
  }
}
