locals {
  config = jsondecode(file(var.project_config_path))

  default_cloud  = local.config.default_cloud
  default_region = local.config.default_region

  resolved_vms = {
    for name, vm in local.config.vms : name => merge(
      vm,
      {
        cloud       = try(vm.cloud, local.default_cloud)
        region_key  = try(vm.region, local.default_region)
        internal_ip = try(vm.internal_ip, null)

        provider_region = local.config.cloud_mappings.regions[
          try(vm.region, local.default_region)
        ][try(vm.cloud, local.default_cloud)].region

        provider_zone = local.config.cloud_mappings.regions[
          try(vm.region, local.default_region)
        ][try(vm.cloud, local.default_cloud)].zone

        machine_type = local.config.cloud_mappings.sizes[
          vm.size
        ][try(vm.cloud, local.default_cloud)]

        disk_type = local.config.cloud_mappings.disk_types[
          vm.boot_disk.type
        ][try(vm.cloud, local.default_cloud)]

        image_settings = local.config.cloud_mappings.images[
          vm.image
        ][try(vm.cloud, local.default_cloud)]
      }
    )
  }

  gcp_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.cloud == "gcp"
  }

  aws_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.cloud == "aws"
  }

  bastion_vm = local.resolved_vms.bastion

  workload_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.role != "bastion"
  }

  gcp_project_id = try(local.config.clouds.gcp.project_id, null)

  gcp_regions = distinct([
    for vm in values(local.gcp_vms) : vm.provider_region
  ])

  gcp_zones = distinct([
    for vm in values(local.gcp_vms) : vm.provider_zone
  ])

  aws_regions = distinct([
    for vm in values(local.aws_vms) : vm.provider_region
  ])

  aws_zones = distinct([
    for vm in values(local.aws_vms) : vm.provider_zone
  ])

  gcp_region = try(local.gcp_regions[0], null)
  gcp_zone   = try(local.gcp_zones[0], null)

  aws_region = try(local.aws_regions[0], local.config.cloud_mappings.regions[
    local.default_region
  ].aws.region)
  aws_zone = try(local.aws_zones[0], null)

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
    local.config.common_labels,
  )
}

resource "terraform_data" "configuration_validation" {
  input = local.resource_prefix

  lifecycle {
    precondition {
      condition     = length(local.gcp_vms) == 0 || local.gcp_project_id != null
      error_message = "clouds.gcp.project_id is required when any VM resolves to GCP."
    }

    precondition {
      condition     = alltrue([for vm in values(local.gcp_vms) : vm.internal_ip != null])
      error_message = "Every GCP VM must define internal_ip; AWS VMs may omit it for provider assignment."
    }

    precondition {
      condition     = length(local.gcp_regions) <= 1 && length(local.gcp_zones) <= 1
      error_message = "The current GCP network supports one resolved region and zone per deployment."
    }

    precondition {
      condition     = length(local.aws_regions) <= 1 && length(local.aws_zones) <= 1
      error_message = "The current AWS VPC supports one resolved region and availability zone per deployment."
    }
  }
}
