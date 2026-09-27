locals {
  azure_cloud_config       = lookup(local.config.clouds, "azure", {})
  azure_primary_region_key = local.config.location.region

  azure_explicit_vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      azure_region = lookup(vm, "azure_region", local.azure_primary_region_key)
    })
    if lookup(vm, "cloud", local.config.default_cloud) == "azure"
  }

  azure_explicit_bastions = {
    for name, vm in local.azure_explicit_vms : name => vm
    if vm.role == "bastion"
  }

  azure_workload_vms = {
    for name, vm in local.azure_explicit_vms : name => vm
    if vm.role != "bastion"
  }

  azure_auto_bastion = (
    length(local.azure_workload_vms) > 0 &&
    length(local.azure_explicit_bastions) == 0
    ) ? {
    azure-bastion = merge(local.config.vms.bastion, {
      cloud            = "azure"
      azure_region     = local.azure_primary_region_key
      internal_ip      = try(local.config.vms.bastion.internal_ips.azure, "10.2.0.10")
      assign_public_ip = true
    })
  } : {}

  azure_vms = merge(local.azure_explicit_vms, local.azure_auto_bastion)

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
      local.config.network,
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

  azure_management_source_cidrs = length(local.azure_vms) == 0 ? [] : [
    local.azure_region_networks[local.azure_primary_region_key].management_subnet_cidr
  ]

  azure_trusted_vnet_cidrs = [
    for region_key in local.azure_region_keys :
    local.azure_region_networks[region_key].vnet_cidr
  ]

  azure_vm_outputs = merge({}, [
    for regional_module in values(module.azure_vm) : regional_module.vms
  ]...)
}

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

resource "azurerm_virtual_network_peering" "primary_to_region" {
  for_each = local.azure_peer_regions

  name                      = "${local.config.name_prefix}-${local.config.environment}-${local.azure_primary_region_key}-to-${each.key}"
  resource_group_name       = module.azure_network[local.azure_primary_region_key].resource_group_name
  virtual_network_name      = module.azure_network[local.azure_primary_region_key].virtual_network_name
  remote_virtual_network_id = module.azure_network[each.key].virtual_network_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "region_to_primary" {
  for_each = local.azure_peer_regions

  name                      = "${local.config.name_prefix}-${local.config.environment}-${each.key}-to-${local.azure_primary_region_key}"
  resource_group_name       = module.azure_network[each.key].resource_group_name
  virtual_network_name      = module.azure_network[each.key].virtual_network_name
  remote_virtual_network_id = module.azure_network[local.azure_primary_region_key].virtual_network_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
