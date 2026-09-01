locals {
  config = jsondecode(file(var.project_config_path))

  default_cloud = lookup(local.config, "default_cloud", "")

  vm_clouds = {
    for name, vm in local.config.vms : name => lookup(vm, "cloud", local.default_cloud)
  }

  clouds = distinct(values(local.vm_clouds))

  has_gcp = contains(local.clouds, "gcp")
  has_aws = contains(local.clouds, "aws")

  location = lookup(local.config, "location", "")

  region = {
    for cloud in local.supported_clouds :
    cloud => lookup(lookup(local.catalog.region, cloud, {}), local.location, null)
  }

  zone = {
    for cloud in local.supported_clouds :
    cloud => lookup(lookup(local.catalog.zone, cloud, {}), local.location, null)
  }

  gcp_project_id      = lookup(lookup(local.config, "gcp", {}), "project_id", null)
  aws_provider_region = coalesce(local.region["aws"], "us-east-1")

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
    local.config.common_labels,
  )

  subnet_cidr = {
    management = local.config.network.management_subnet_cidr
    workload   = local.config.network.workload_subnet_cidr
  }

  public_subnet_vms = {
    for name, vm in local.config.vms : name => (
      vm.role == "bastion" ||
      (lookup(local.public_ip_needs_public_subnet, local.vm_clouds[name], false) && vm.assign_public_ip)
    )
  }

  vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      cloud  = local.vm_clouds[name]
      subnet = local.public_subnet_vms[name] ? "management" : "workload"

      machine_type = lookup(
        lookup(local.catalog.size, local.vm_clouds[name], {}),
        vm.size, null
      )

      boot_disk_type = lookup(
        lookup(local.catalog.disk_type, local.vm_clouds[name], {}),
        vm.boot_disk.type, null
      )

      image = lookup(
        lookup(local.catalog.os, local.vm_clouds[name], {}),
        vm.os, null
      )
    })
  }

  misplaced_ips = [
    for name, vm in local.vms : name
    if cidrhost(local.subnet_cidr[vm.subnet], 0) !=
    cidrhost("${vm.internal_ip}/${split("/", local.subnet_cidr[vm.subnet])[1]}", 0)
  ]

  aws_reserved_ips = [
    for name, vm in local.vms : name
    if vm.cloud == "aws" && contains(
      [for i in range(4) : cidrhost(local.subnet_cidr[vm.subnet], i)],
      vm.internal_ip
    )
  ]

  gcp_vms = { for name, vm in local.vms : name => vm if vm.cloud == "gcp" }
  aws_vms = { for name, vm in local.vms : name => vm if vm.cloud == "aws" }

  bastion_vm = local.config.vms.bastion

  workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }

  secret_reading_vms = {
    for name, vm in local.workload_vms : name => vm
    if length(vm.secret_mappings) > 0
  }

  gcp_secret_reading_vms = {
    for name, vm in local.secret_reading_vms : name => vm
    if local.vm_clouds[name] == "gcp"
  }

  aws_secret_reading_vms = {
    for name, vm in local.secret_reading_vms : name => vm
    if local.vm_clouds[name] == "aws"
  }
}
