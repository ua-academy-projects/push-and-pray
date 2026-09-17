output "log_group_name" {
  description = "Traefik CloudWatch destination; null when disabled."
  value       = try(aws_cloudwatch_log_group.traefik[0].name, null)
}
output "sns_topic_arn" {
  description = "Operational alert topic; recipients must confirm their email subscriptions."
  value       = try(aws_sns_topic.alerts[0].arn, null)
}
output "dashboard_name" {
  value = try(aws_cloudwatch_dashboard.operations[0].dashboard_name, null)
}
output "alarm_arns" {
  value = merge({ for k, v in aws_cloudwatch_metric_alarm.vm : k => v.arn }, { for k, v in aws_cloudwatch_metric_alarm.http : k => v.arn }, { for k, v in aws_cloudwatch_metric_alarm.synthetic : "synthetic-${k}" => v.arn }, { for k, v in aws_cloudwatch_metric_alarm.application : k => v.arn }, { for k, v in aws_cloudwatch_metric_alarm.database : "database-${k}" => v.arn })
}
output "agent_configurations" {
  description = "JSON configurations keyed by VM name. Deploy with CloudWatch Agent after its IAM permissions are ready."
  value       = local.agent_configurations
}
output "canary_name" {
  value = try(aws_synthetics_canary.health[0].name, null)
}
