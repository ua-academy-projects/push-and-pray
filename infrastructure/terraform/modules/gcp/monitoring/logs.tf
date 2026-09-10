resource "google_logging_project_bucket_config" "traefik" {
  count          = local.logs_enabled ? 1 : 0
  project        = local.project_id
  location       = "global"
  bucket_id      = "${local.resource_prefix}-traefik"
  retention_days = local.settings.log_retention_days
  depends_on     = [google_project_service.monitoring]
}
resource "google_logging_project_sink" "traefik" {
  count       = local.logs_enabled ? 1 : 0
  project     = local.project_id
  name        = "${local.resource_prefix}-traefik"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.traefik[0].id}"
  filter      = local.access_filter
  # Same-project Logging buckets require no cross-project writer grant.
  unique_writer_identity = true
}
# Only these UI access logs are removed from _Default, after their sink exists.
resource "google_logging_project_exclusion" "traefik_default" {
  count       = local.logs_enabled ? 1 : 0
  project     = local.project_id
  name        = "${local.resource_prefix}-traefik-routed"
  description = "Traefik logs are retained in the dedicated project monitoring bucket."
  filter      = local.access_filter
  depends_on  = [google_logging_project_sink.traefik]
}
resource "google_logging_metric" "http" {
  for_each = local.logs_enabled ? local.http_filters : {}
  project  = local.project_id
  name     = "${local.resource_prefix}-${each.key}"
  filter   = "${local.access_filter} AND ${each.value}"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
  depends_on = [google_project_service.monitoring]
}
