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

output "gcp_monitoring" {
  description = "GCP monitoring identifiers and Ops Agent YAML for Ansible deployment."
  value = {
    log_bucket_id            = module.gcp_monitoring.log_bucket_id
    log_filter               = module.gcp_monitoring.log_filter
    notification_channel_ids = module.gcp_monitoring.notification_channel_ids
    dashboard_id             = module.gcp_monitoring.dashboard_id
    alert_policy_ids         = module.gcp_monitoring.alert_policy_ids
    uptime_check_id          = module.gcp_monitoring.uptime_check_id
    agent_configurations     = module.gcp_monitoring.agent_configurations
  }
}
