output "config" {
  description = "Raw shared configuration for non-provider-specific resource arguments."
  value       = local.config
}

output "cloud_config" {
  description = "Provider catalog selected by cloud."
  value       = local.cloud_config
}

output "cloud" {
  value = local.cloud
}

output "network" {
  description = "Cloud-specific network configuration merged over the shared defaults."
  value       = local.network
}

output "manage_db" {
  value = local.manage_db
}

output "database" {
  value = local.database
}

output "managed_database_enabled" {
  value = local.manage_db && local.database_cloud == local.cloud
}

output "selected_count" {
  value = length(local.selected_vms)
}

output "resolved_vms" {
  description = "Selected VMs with abstract profiles resolved to provider values."
  value       = local.resolved_vms
}

output "provisionable_vms" {
  description = "Resolved VMs whose machine, image and disk profiles exist."
  value       = local.provisionable_vms
}

output "workload_vms" {
  value = local.workload_vms
}

output "bastion_count" {
  value = length(local.selected_bastions)
}

output "bastion_key" {
  value = try(keys(local.bastions)[0], null)
}

output "bastion" {
  value = try(values(local.bastions)[0], null)
}

output "location" {
  value = local.location
}

output "location_valid" {
  value = local.location.region != null && local.location.zone != null
}

output "profiles_valid" {
  value = length(local.resolved_vms) == length(local.provisionable_vms)
}

output "configuration_valid" {
  value = (
    local.all_clouds_valid &&
    local.database_valid &&
    length(local.resolved_vms) == length(local.provisionable_vms) &&
    (length(local.selected_vms) == 0 || (
      local.location.region != null &&
      local.location.zone != null
    ))
  )
}

output "resource_prefix" {
  value = local.resource_prefix
}

output "common_metadata" {
  value = local.common_metadata
}

output "all_secret_ids" {
  value = local.all_secret_ids
}

output "workload_secret_pairs" {
  value = local.workload_secret_pairs
}

output "bastion_nat" {
  value = lookup(local.cloud_config, "bastion_nat", true)
}

output "free_tier_guardrails" {
  value = lookup(local.cloud_config, "free_tier_guardrails", true)
}
