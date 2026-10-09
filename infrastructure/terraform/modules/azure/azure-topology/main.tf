check "azure_regions_are_configured" {
  assert {
    condition = alltrue([
      for region_key in local.azure_region_keys :
      contains(keys(local.azure_cloud_config.regions), region_key)
    ])
    error_message = "Every Azure VM azure_region must exist in clouds.azure.regions."
  }
}

check "azure_regional_vnet_cidrs_are_unique" {
  assert {
    condition = length(local.azure_trusted_vnet_cidrs) == length(distinct(
      local.azure_trusted_vnet_cidrs
    ))
    error_message = "Each Azure region must use a unique VNet CIDR."
  }
}
