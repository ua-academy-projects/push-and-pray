output "dashboard_name" {
  value = google_monitoring_dashboard.main.id
}

output "contract" {
  description = "Provider-neutral monitoring resource identifiers."
  value = {
    dashboard_id = google_monitoring_dashboard.main.id
    alert_policy_ids = concat(
      [for policy in google_monitoring_alert_policy.cpu_high : policy.name],
      [for policy in google_monitoring_alert_policy.memory_high : policy.name],
      [for policy in google_monitoring_alert_policy.disk_high : policy.name],
      [google_monitoring_alert_policy.http_5xx.name],
      [for policy in google_monitoring_alert_policy.database_cpu_high : policy.name],
      [for policy in google_monitoring_alert_policy.database_disk_high : policy.name],
      [google_monitoring_alert_policy.uptime.name],
    )
    availability_id = google_monitoring_uptime_check_config.application.name
    log_metric_ids  = [google_logging_metric.http_5xx.id]
  }
}
