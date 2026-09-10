resource "google_monitoring_notification_channel" "email" {
  count = var.has_selected_vms ? 1 : 0

  display_name = "${local.resource_prefix}-email"
  type         = "email"

  labels = {
    email_address = var.config.monitoring.notification_email
  }
}