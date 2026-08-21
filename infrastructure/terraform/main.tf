module "network" {
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port      = local.config.bastion.ssh_port
  bastion_allowed_cidrs = local.config.bastion.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
}

module "bastion" {
  source = "./modules/bastion"

  resource_prefix = local.resource_prefix
  subnetwork_id   = module.network.management_subnet_id
  network_tags = distinct(concat(
    [module.network.network_tags.bastion],
    [
      for tag in local.config.bastion.network_tags :
      "${local.resource_prefix}-${tag}"
    ],
  ))

  machine_type      = local.config.bastion.machine_type
  image             = local.config.bastion.image
  boot_disk_size_gb = local.config.bastion.boot_disk.size_gb
  boot_disk_type    = local.config.bastion.boot_disk.type
  preemptible       = local.config.bastion.preemptible

  labels = merge(local.common_labels, try(local.config.bastion.labels, {}))
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.config.workloads

  name          = "${local.resource_prefix}-${each.key}"
  subnetwork_id = module.network.workload_subnet_id
  role          = each.value.role
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
}

locals {
  secret_ids = toset(flatten([
    for workload in values(local.config.workloads) : concat(
      workload.secret_ids,
      values(try(workload.secret_bindings, {})),
    )
  ]))

}

module "secret_publisher_iam" {
  source = "./modules/secret-publisher-iam"

  secret_ids                = local.secret_ids
  publisher_service_account = local.config.deployment_identity
}
