output "metrics" {
  description = "The watched metrics - namespace, name, statistic, dimension, threshold and comparison - for alerting to build one alarm per instance and entry."
  value       = local.metrics
}

output "dashboard_arn" {
  description = "ARN of the dashboard."
  value       = aws_cloudwatch_dashboard.hosts.dashboard_arn
}
