module "network" {
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port      = local.bastion_vm.ssh_port
  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

module "bastion" {
  source = "./modules/bastion"

  resource_prefix = local.resource_prefix
  subnetwork_id   = module.network.management_subnet_id
  network_tags = distinct(concat(
    [module.network.network_tags.bastion],
    [
      for tag in local.bastion_vm.network_tags :
      "${local.resource_prefix}-${tag}"
    ],
  ))

  machine_type      = local.bastion_vm.machine_type
  image             = local.bastion_vm.image
  internal_ip       = local.bastion_vm.internal_ip
  boot_disk_size_gb = local.bastion_vm.boot_disk.size_gb
  boot_disk_type    = local.bastion_vm.boot_disk.type

  labels = merge(local.common_labels, try(local.bastion_vm.labels, {}))

  depends_on = [google_project_service.required]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.workload_vms

  name                = "${local.resource_prefix}-${each.key}"
  subnetwork_id       = module.network.workload_subnet_id
  role                = each.value.role
  automation_role     = each.value.automation_role
  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  network_tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]

  machine_type = each.value.machine_type
  image        = each.value.image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk.type

  assign_public_ip = each.value.assign_public_ip


  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )

  depends_on = [google_project_service.required]
}
