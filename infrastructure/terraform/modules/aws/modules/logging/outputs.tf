output "log_group_name" {
  description = "Log group the journals land in. Alert filters read it."
  value       = aws_cloudwatch_log_group.journald.name
}

output "log_group_arn" {
  description = "ARN of the log group."
  value       = aws_cloudwatch_log_group.journald.arn
}
