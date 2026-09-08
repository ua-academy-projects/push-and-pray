output "summary" {
  description = "Identifiers useful for opening or integrating the created observability resources."
  value = {
    dashboard_id         = google_monitoring_dashboard.overview.id
    notification_channel = google_monitoring_notification_channel.email.name
    uptime_check_id      = try(google_monitoring_uptime_check_config.ui[0].uptime_check_id, null)
    cpu_alert_policy     = google_monitoring_alert_policy.high_cpu.name
    disk_alert_policy    = google_monitoring_alert_policy.high_disk.name
    log_alert_policy     = try(google_monitoring_alert_policy.container_errors[0].name, null)
    uptime_alert_policy  = try(google_monitoring_alert_policy.ui_unavailable[0].name, null)
    budget_id            = try(google_billing_budget.project[0].id, null)
  }
}
