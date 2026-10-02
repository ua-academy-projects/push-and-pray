locals {
  enabled = (
    var.config.default_cloud == "aws" &&
    var.config.managed_database
  )

  settings = local.enabled ? (
    var.config.database_profile_map[var.config.database_profile].aws
  ) : null
}
