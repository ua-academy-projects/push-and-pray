module "network" {
  count  = local.enabled ? 1 : 0
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = var.config.network.management_subnet_cidr
  workload_subnet_cidr   = var.config.network.workload_subnet_cidr

  bastion_ssh_port      = try(local.bastion_vm.ssh_port, 22)
  bastion_allowed_cidrs = try(local.bastion_vm.allowed_cidrs, [])

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]

  history_api_port = var.config.service_ports.history_api
  postgresql_port  = var.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.vms
  zone     = local.zone

  name          = "${local.resource_prefix}-${each.key}"
  role          = each.value.role
  subnetwork_id = lookup(local.subnet_by_role, each.value.role)

  machine_type = each.value.machine_type
  image        = each.value.image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk.type

  assign_public_ip = each.value.assign_public_ip
  # ssh_port         = lookup(each.value, "ssh_port", 22)

  # registry_repository = var.config.registry.repository
  # image_sha           = var.config.registry.image_sha
  ssh_users = var.config.ssh_users

  network_tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    { role = each.value.role },
  )

  depends_on = [google_project_service.required]
}