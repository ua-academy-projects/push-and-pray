output "topic_arn" {
  description = "The SNS topic every alarm publishes to."
  value       = aws_sns_topic.alerts.arn
}
