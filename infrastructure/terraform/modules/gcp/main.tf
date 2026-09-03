module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.config.regions[local.config.default_region][var.cloud_key].region

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./vm"
  for_each = local.resolved_vms

  name          = "${local.resource_prefix}-${each.key}"
  role          = each.value.role
  region        = each.value.location.region
  zone          = each.value.location.zone
  subnetwork_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : module.network[0].workload_subnet_id

  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  ssh_users           = local.config.ssh_users
  network_tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]

  machine_type = each.value.instance_type
  image        = each.value.image_config.reference
  internal_ip  = each.value.internal_ip
  ssh_port     = lookup(each.value, "ssh_port", 22)

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type
  assign_public_ip  = each.value.assign_public_ip

  labels = merge(
    lookup(each.value, "labels", {}),
    local.common_labels,
    {
      role  = each.value.role
      cloud = each.value.effective_cloud
    },
  )

  depends_on = [google_project_service.required]
}
