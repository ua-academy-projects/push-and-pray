resource "google_project_service" "secret_manager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

module "network" {
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  bastion_ssh_port      = local.config.bastion.ssh_port
  bastion_allowed_cidrs = local.config.bastion.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
}

module "bastion" {
  source = "./modules/bastion"

  resource_prefix = local.resource_prefix
  subnetwork_id   = module.network.management_subnet_id
  network_tag     = module.network.network_tags.bastion

  machine_type      = local.config.bastion.machine_type
  image             = local.config.bastion.image
  boot_disk_size_gb = local.config.bastion.boot_disk.size_gb
  boot_disk_type    = local.config.bastion.boot_disk.type

  labels = local.common_labels
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.config.workloads

  name          = "${local.resource_prefix}-${each.key}"
  subnetwork_id = module.network.workload_subnet_id
  network_tag   = module.network.network_tags[each.value.role]
  network_tags  = distinct(concat(each.value.network_tags, [module.network.network_tags[each.value.role]]))

  machine_type = each.value.machine_type
  image        = each.value.boot_image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk.type

  assign_public_ip = each.value.assign_public_ip

  automation_role = each.value.automation_role
  image_tag       = each.value.image_tag
  secret_bindings = try(each.value.secret_bindings, {})
  image_repository = local.config.image_repository
  compose_repository_url = local.config.compose_repository_url
  docker_engine_version = local.config.docker_engine_version
  service_ips = {
    for workload in values(local.config.workloads) : workload.role => workload.internal_ip
  }

  labels = merge(local.common_labels, {
    role = each.value.role
  })
}

locals {
  secret_ids = toset(flatten([
    for workload in values(local.config.workloads) : concat(
      try(workload.secret_ids, []),
      values(try(workload.secret_bindings, {}))
    )
  ]))

  secret_accessors = {
    for secret_id in local.secret_ids : secret_id => toset([
      for workload_name, workload in local.config.workloads : module.vm[workload_name].service_account_email
      if contains(concat(try(workload.secret_ids, []), values(try(workload.secret_bindings, {}))), secret_id)
    ])
  }
}

module "secret_manager" {
  source = "./modules/secret-manager"

  secret_ids = local.secret_ids
  accessors  = local.secret_accessors
  labels     = local.common_labels

  depends_on = [google_project_service.secret_manager]
}