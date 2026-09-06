module "network" {
  source = "./modules/network"
  count  = length(local.my_vms) > 0 ? 1 : 0

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.profile.subnets.management
  workload_subnet_cidr   = local.profile.subnets.workload

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = var.config.service_ports.history_api
  postgresql_port  = var.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name          = "${local.resource_prefix}-${each.key}"
  subnetwork_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : module.network[0].workload_subnet_id
  role          = each.value.role
  ssh_users     = var.config.ssh_users
  network_tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]

  machine_type   = local.profile.machine_sizes[each.value.size]
  image          = local.profile.images[each.value.image]
  boot_disk_type = local.profile.disk_types[each.value.boot_disk.type]

  internal_ip       = each.value.internal_ip
  boot_disk_size_gb = each.value.boot_disk.size_gb
  assign_public_ip  = each.value.assign_public_ip

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )

  depends_on = [google_project_service.required]
}
