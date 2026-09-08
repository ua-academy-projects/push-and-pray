locals {
  notification_channels = [google_monitoring_notification_channel.email.name]

  cpu_filter  = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.label.project_id=\"${var.project_id}\""
  disk_filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.label.project_id=\"${var.project_id}\" AND metric.label.state=\"used\""
  log_filter  = "resource.type=\"gce_instance\" AND jsonPayload.log=~\"${var.settings.logs.error_pattern}\""

  agent_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  agent_role_members = {
    for pair in setproduct(keys(var.service_account_emails), local.agent_roles) :
    "${pair[0]}:${pair[1]}" => {
      role   = pair[1]
      member = "serviceAccount:${var.service_account_emails[pair[0]]}"
    }
  }
}
