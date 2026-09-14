locals {
  enabled         = var.config.default_cloud == "gcp" && var.config.default_db == "cloud"
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  settings        = local.enabled ? var.config.database_profile_map[var.config.database_profile].gcp : null
  region          = local.enabled ? var.config.region_map[var.config.region].gcp.region : null
  labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
  # Select the certificate name for PSA, not the PSC/public endpoint.
  dns_name = local.enabled ? trimsuffix(one([
    for dns in google_sql_database_instance.this[0].dns_names : dns.name
    if dns.connection_type == "PRIVATE_SERVICES_ACCESS" && dns.dns_scope == "INSTANCE"
  ]), ".") : null
}
