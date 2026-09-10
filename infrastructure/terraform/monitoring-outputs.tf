output "aws_monitoring" {
  description = "AWS monitoring identifiers and non-secret agent configurations for deployment."
  value = {
    log_group_name       = module.aws_monitoring.log_group_name
    sns_topic_arn        = module.aws_monitoring.sns_topic_arn
    dashboard_name       = module.aws_monitoring.dashboard_name
    alarm_arns           = module.aws_monitoring.alarm_arns
    canary_name          = module.aws_monitoring.canary_name
    agent_configurations = module.aws_monitoring.agent_configurations
  }
}
