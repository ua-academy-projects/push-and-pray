locals {
  enabled = var.config.default_cloud == "aws"

  console_client_secret_id = try(var.config.headlamp.oidc.client_secret_secret_id, "")

  console_uses_oidc = try(var.config.headlamp.auth_mode, "token") == "oidc"

  console_secret_ids = (
    try(var.config.headlamp.enabled, false)
    && local.console_uses_oidc
    && local.console_client_secret_id != ""
    ? [local.console_client_secret_id]
    : []
  )

  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}
