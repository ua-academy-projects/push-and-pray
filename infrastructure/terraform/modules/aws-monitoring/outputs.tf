output "sns_topic_arn" {
  description = "ARN of the SNS topic used for AWS alerts."
  value       = try(aws_sns_topic.alerts[0].arn, null)
}

output "alarm_names" {
  description = "CloudWatch alarm names keyed by instance name."

  value = {
    for name, alarm in aws_cloudwatch_metric_alarm.instance_status :
    name => alarm.alarm_name
  }
}
