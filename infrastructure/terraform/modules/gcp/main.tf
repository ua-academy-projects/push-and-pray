module "config" {
  source = "./config"

  project_config_path = var.project_config_path
}

resource "terraform_data" "configuration" {
  count = module.config.selected_count > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = module.config.bastion_count <= 1
      error_message = "GCP may contain at most one VM with role bastion."
    }
  }
}

resource "google_project_service" "required" {
  for_each = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
    ) ? toset([
      "compute.googleapis.com",
      "iam.googleapis.com",
      "secretmanager.googleapis.com",
  ]) : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

module "network" {
  source = "./network"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? 1 : 0

  resource_prefix = module.config.resource_prefix

  management_subnet_cidr = module.config.config.network.management_subnet_cidr
  workload_subnet_cidr   = module.config.config.network.workload_subnet_cidr
  ui_public_ports = [
    for port in module.config.config.network.ui_public_ports : tostring(port)
  ]

  enable_bastion               = module.config.bastion != null
  bastion_ssh_port             = try(module.config.bastion.ssh_port, 22)
  bastion_allowed_cidrs        = try(module.config.bastion.allowed_cidrs, [])
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  history_api_port             = module.config.config.service_ports.history_api
  postgresql_port              = module.config.config.service_ports.postgresql

  depends_on = [google_project_service.required, terraform_data.configuration]
}

# trivy:ignore:AVD-GCP-0031 Public IPs are restricted to UI and bastion by module validation.
module "vm" {
  source = "./vm"
  for_each = {
    for name, vm in module.config.provisionable_vms : name => vm
    if module.config.configuration_valid
  }

  name          = "${module.config.resource_prefix}-${each.key}"
  subnetwork_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : module.network[0].workload_subnet_id
  role          = each.value.role

  registry_repository = module.config.config.registry.repository
  image_sha           = module.config.config.registry.image_sha
  ssh_users           = module.config.config.ssh_users
  network_tags        = each.value.network_tags_effective

  machine_type      = each.value.machine_type
  image             = each.value.image
  internal_ip       = each.value.internal_ip
  ssh_port          = each.value.ssh_port
  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type
  assign_public_ip  = each.value.assign_public_ip
  labels            = each.value.metadata

  depends_on = [google_project_service.required, terraform_data.configuration]
}

resource "google_secret_manager_secret" "this" {
  for_each = toset(
    module.config.configuration_valid ? module.config.all_secret_ids : []
  )

  secret_id = each.value
  labels    = module.config.common_metadata

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in module.config.workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
    if module.config.configuration_valid
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.vm[each.value.vm_name].service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = {
    for pair in setproduct(
      sort(module.config.all_secret_ids),
      var.secret_version_managers,
      ) : "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
    if module.config.configuration_valid
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
