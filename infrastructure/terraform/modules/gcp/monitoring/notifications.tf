resource "google_monitoring_notification_channel" "email" {
  for_each     = local.recipients
  project      = local.project_id
  display_name = "${local.resource_prefix} monitoring ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
  user_labels  = local.common_labels
  depends_on   = [google_project_service.monitoring]
}
