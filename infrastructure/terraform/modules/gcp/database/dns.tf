resource "google_dns_managed_zone" "database" {
  count   = local.enabled ? 1 : 0
  project = var.config.clouds.gcp.project_id
  name    = "${local.resource_prefix}-database"
  # An exact-host zone avoids shadowing other Cloud SQL instances' names.
  dns_name   = "${local.dns_name}."
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = var.network.cloud_sql.network_id
    }
  }
  depends_on = [google_project_service.database]
}

resource "google_dns_record_set" "database" {
  count        = local.enabled ? 1 : 0
  project      = var.config.clouds.gcp.project_id
  managed_zone = google_dns_managed_zone.database[0].name
  name         = google_dns_managed_zone.database[0].dns_name
  type         = "A"
  ttl          = var.config.clouds.gcp.cloud_sql_network.dns_ttl_seconds
  rrdatas      = [google_sql_database_instance.this[0].private_ip_address]
}
