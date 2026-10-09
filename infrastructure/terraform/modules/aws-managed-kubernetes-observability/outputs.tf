output "dashboard_name" {
  description = "CloudWatch dashboard for the EKS cluster."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "notification_topic_arns" {
  description = "Terraform-managed SNS topics created for EKS alarm email."
  value       = { for region, topic in aws_sns_topic.email : region => topic.arn }
}
