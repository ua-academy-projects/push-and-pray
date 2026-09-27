output "notification_channel_name" {
  description = "Resource name of the email notification channel used for GCP alerts."
  value       = try(google_monitoring_notification_channel.email[0].name, null)
}

output "cpu_alert_policy_names" {
  description = "GCP CPU alert policy resource names keyed by instance name."

  value = {
    for instance_name, policy in google_monitoring_alert_policy.high_cpu :
    instance_name => policy.name
  }
}

output "dashboard_id" {
  description = "ID of the GCP infrastructure monitoring dashboard."
  value       = try(google_monitoring_dashboard.infrastructure[0].id, null)
}


