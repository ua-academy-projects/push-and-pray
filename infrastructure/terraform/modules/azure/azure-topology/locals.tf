locals {
  azure_cloud_config       = lookup(var.config.clouds, "azure", {})
  azure_primary_region_key = var.config.location.region

  azure_explicit_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      azure_region = lookup(vm, "azure_region", local.azure_primary_region_key)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "azure"
  }

  azure_vms = local.azure_explicit_vms

  azure_region_keys = distinct([
    for vm in values(local.azure_vms) : vm.azure_region
  ])

  azure_vms_by_region = {
    for region_key in local.azure_region_keys : region_key => {
      for name, vm in local.azure_vms : name => vm
      if vm.azure_region == region_key
    }
  }

  azure_region_locations = {
    for region_key in local.azure_region_keys :
    region_key => try(local.azure_cloud_config.regions[region_key], null)
  }

  azure_region_networks = {
    for region_key in local.azure_region_keys : region_key => merge(
      var.config.network,
      lookup(local.azure_cloud_config, "network", {}),
      try(local.azure_cloud_config.regional_networks[region_key], {}),
    )
  }

  azure_region_name_suffixes = {
    for region_key in local.azure_region_keys :
    region_key => region_key == local.azure_primary_region_key ? "" : region_key
  }

  azure_peer_regions = {
    for region_key, vms in local.azure_vms_by_region : region_key => vms
    if region_key != local.azure_primary_region_key
  }

  azure_trusted_vnet_cidrs = [
    for region_key in local.azure_region_keys :
    local.azure_region_networks[region_key].vnet_cidr
  ]
}
