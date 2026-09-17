output "deployment" {
  description = "Versioned provider-neutral deployment contract."
  value       = local.deployment

  precondition {
    condition = (
      local.cloud_provider == var.provider_name &&
      contains(["portable", "managed"], local.data_profile) &&
      local.runtime == "compose" &&
      local.ui != null &&
      local.bastion != null &&
      local.database.host != null
    )
    error_message = "The deployment contract requires a matching global provider, compose runtime, UI, bastion, and resolvable database endpoint."
  }
}
