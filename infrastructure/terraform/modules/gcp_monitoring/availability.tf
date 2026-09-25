resource "google_monitoring_uptime_check_config" "ui" {
  for_each = local.ui_vms

  project            = var.config.gcp.project_id
  display_name       = "${local.resource_prefix}-ui"
  timeout            = "10s"
  period             = "60s"
  checker_type       = "STATIC_IP_CHECKERS"
  log_check_failures = true

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.config.gcp.project_id
      host       = var.config.vms[each.key].public_endpoint.domain
    }
  }

  http_check {
    path           = var.config.monitoring.ui_health_path
    port           = 443
    request_method = "GET"
    use_ssl        = true
    validate_ssl   = true
  }
}
