locals {
  enabled = (
    var.config.default_cloud == "azure" &&
    var.config.managed_database
  )

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  settings = local.enabled ? (
    var.config.database_profile_map[var.config.database_profile].azure
  ) : null

  zone = local.enabled ? var.config.region_map[var.config.region].azure.availability_zone : null

  admin_username = "oil_tracker_admin"

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  ca_certificate_urls = [
    "https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem",
    "https://www.microsoft.com/pkiops/certs/Microsoft%20RSA%20Root%20Certificate%20Authority%202017.crt",
  ]
}
