resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.resource_prefix} operations email"
  type         = "email"

  labels = {
    email_address = var.settings.notification_email
  }

  user_labels = var.labels
}
