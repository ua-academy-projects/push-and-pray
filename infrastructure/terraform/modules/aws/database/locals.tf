locals {
  enabled = (
    var.config.default_cloud == "aws" &&
    var.config.default_db == "cloud"
  )

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  settings = local.enabled ? (
    var.config.database_profile_map[var.config.database_profile].aws
  ) : null
}
