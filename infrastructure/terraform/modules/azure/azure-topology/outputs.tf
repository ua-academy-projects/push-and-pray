output "cloud_config" {
  value = local.azure_cloud_config
}

output "primary_region_key" {
  value = local.azure_primary_region_key
}

output "vms" {
  value = local.azure_vms
}

output "vms_by_region" {
  value = local.azure_vms_by_region
}

output "region_locations" {
  value = local.azure_region_locations
}

output "region_networks" {
  value = local.azure_region_networks
}

output "region_name_suffixes" {
  value = local.azure_region_name_suffixes
}

output "peer_regions" {
  value = local.azure_peer_regions
}

output "trusted_vnet_cidrs" {
  value = local.azure_trusted_vnet_cidrs
}
