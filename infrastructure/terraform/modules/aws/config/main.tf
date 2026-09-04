locals {
  config       = jsondecode(file(var.project_config_path))
  cloud        = "aws"
  cloud_config = lookup(local.config.clouds, local.cloud, {})
  defaults     = local.config.defaults

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"
  common_metadata = merge(
    lookup(local.config, "common_labels", {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
    },
  )

  selected_vms = {
    for name, vm in local.config.vms : name => vm
    if lower(lookup(vm, "cloud", local.config.default_cloud)) == local.cloud
  }

  all_clouds_valid = alltrue([
    for vm in values(local.config.vms) :
    contains(
      ["aws", "gcp"],
      lower(lookup(vm, "cloud", local.config.default_cloud)),
    )
  ])

  resolved_vms = {
    for name, vm in local.selected_vms : name => merge(vm, {
      cloud           = local.cloud
      machine_profile = lookup(vm, "machine_profile", local.defaults.machine_profile)
      image_profile   = lookup(vm, "image_profile", local.defaults.image_profile)
      disk_profile    = lookup(vm.boot_disk, "profile", local.defaults.disk_profile)
      machine_type = lookup(
        lookup(local.cloud_config, "machine_types", {}),
        lookup(vm, "machine_profile", local.defaults.machine_profile),
        null,
      )
      image = lookup(
        lookup(local.cloud_config, "images", {}),
        lookup(vm, "image_profile", local.defaults.image_profile),
        null,
      )
      disk_type = lookup(
        lookup(local.cloud_config, "disk_types", {}),
        lookup(vm.boot_disk, "profile", local.defaults.disk_profile),
        null,
      )
      ssh_port      = lookup(vm, "ssh_port", 22)
      allowed_cidrs = lookup(vm, "allowed_cidrs", [])
      network_tags_effective = [
        for tag in vm.network_tags : "${local.resource_prefix}-${tag}"
      ]
      metadata = merge(
        local.common_metadata,
        lookup(vm, "labels", {}),
        {
          application = local.config.name_prefix
          environment = local.config.environment
          managed_by  = "terraform"
          cloud       = local.cloud
          role        = vm.role
          vm_name     = name
        },
      )
    })
  }

  provisionable_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.machine_type != null && vm.image != null && vm.disk_type != null
  }

  selected_bastions = {
    for name, vm in local.resolved_vms : name => vm
    if vm.role == "bastion"
  }
  bastions = {
    for name, vm in local.provisionable_vms : name => vm
    if vm.role == "bastion"
  }

  workload_vms = {
    for name, vm in local.provisionable_vms : name => vm
    if vm.role != "bastion"
  }

  location_source = lookup(
    lookup(local.cloud_config, "locations", {}),
    local.defaults.location_profile,
    {},
  )
  location = {
    region = lookup(local.location_source, "region", null)
    zone   = lookup(local.location_source, "zone", null)
  }

  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) :
    values(workload.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, workload in local.workload_vms : [
      for secret_id in distinct(values(workload.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])
}
