output "log_bucket_id" { value = try(google_logging_project_bucket_config.traefik[0].id, null) }
output "log_filter" { value = local.logs_enabled ? local.access_filter : null }
output "notification_channel_ids" { value = local.notification_channels }
output "dashboard_id" { value = try(google_monitoring_dashboard.operations[0].id, null) }
output "alert_policy_ids" { value = merge({ for k, v in google_monitoring_alert_policy.vm : k => v.name }, { for k, v in google_monitoring_alert_policy.missing : k => v.name }, { for k, v in google_monitoring_alert_policy.http : k => v.name }, { for k, v in google_monitoring_alert_policy.uptime : "uptime-${k}" => v.name }, { for k, v in google_monitoring_alert_policy.application_database : k => v.name }, { for k, v in google_monitoring_alert_policy.collector_missing : "collector-${k}" => v.name }) }
output "uptime_check_id" { value = try(google_monitoring_uptime_check_config.health[0].uptime_check_id, null) }
output "agent_configurations" {
  description = "Ops Agent YAML keyed by VM name; install through Ansible, not Terraform."
  value       = local.agent_configurations
}
