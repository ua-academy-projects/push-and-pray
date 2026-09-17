output "contract" {
  description = "Provider-neutral monitoring resource identifiers."
  value = {
    dashboard_id = aws_cloudwatch_dashboard.main.dashboard_name
    alert_policy_ids = concat(
      [for alarm in aws_cloudwatch_metric_alarm.status_check : alarm.arn],
      [for alarm in aws_cloudwatch_metric_alarm.cpu_high : alarm.arn],
      [for alarm in aws_cloudwatch_metric_alarm.memory_high : alarm.arn],
      [for alarm in aws_cloudwatch_metric_alarm.disk_high : alarm.arn],
      [aws_cloudwatch_metric_alarm.http_5xx.arn],
      [for alarm in aws_cloudwatch_metric_alarm.database_cpu_high : alarm.arn],
      [for alarm in aws_cloudwatch_metric_alarm.database_storage_low : alarm.arn],
      [aws_cloudwatch_metric_alarm.synthetic_failed.arn],
    )
    availability_id = aws_synthetics_canary.api.arn
    log_metric_ids  = [aws_cloudwatch_log_metric_filter.http_5xx.name]
  }
}
