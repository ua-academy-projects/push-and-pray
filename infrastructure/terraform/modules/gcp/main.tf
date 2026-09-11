module "config" {
  source = "../config"

  project_config_path = var.project_config_path
  cloud               = "gcp"
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
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "secretmanager.googleapis.com",
      "servicenetworking.googleapis.com",
      "sqladmin.googleapis.com",
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

  management_subnet_cidr = module.config.network.management_subnet_cidr
  workload_subnet_cidr   = module.config.network.workload_subnet_cidr
  ui_public_ports = [
    for port in module.config.network.ui_public_ports : tostring(port)
  ]

  enable_bastion               = module.config.bastion != null
  bastion_ssh_port             = try(module.config.bastion.ssh_port, 22)
  bastion_allowed_cidrs        = try(module.config.bastion.allowed_cidrs, [])
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  history_api_port             = module.config.config.service_ports.history_api
  postgresql_port              = module.config.config.service_ports.postgresql
  remote_workload_cidrs = toset(
    try(module.config.config.mixed_network.enabled, false) ? try([
      module.config.config.clouds.aws.network.vpc_cidr
    ], []) : []
  )

  depends_on = [google_project_service.required, terraform_data.configuration]
}

module "database" {
  source = "./database"
  count  = module.config.managed_database_enabled && module.config.configuration_valid ? 1 : 0

  project_id           = module.config.cloud_config.project_id
  resource_prefix      = module.config.resource_prefix
  region               = module.config.location.region
  generation           = module.config.database.generation
  engine_version       = module.config.database.engine_version
  database_name        = module.config.database.database_name
  username             = module.config.database.username
  password             = var.database_password
  tier                 = module.config.database.gcp.tier
  disk_size_gb         = module.config.database.gcp.disk_size_gb
  availability_type    = module.config.database.gcp.availability_type
  private_service_cidr = module.config.network.database_private_service_cidr
  network_id           = module.network[0].network_id
  backup_on_delete     = module.config.database.backup_on_delete
  backups_enabled      = module.config.database.backups_enabled
  deletion_protection  = module.config.database.deletion_protection
  backup_run_id        = try(module.config.database.restore.gcp_backup_run_id, null)
  labels               = module.config.common_metadata

  depends_on = [google_project_service.required]
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

  ssh_users    = module.config.config.ssh_users
  network_tags = each.value.network_tags_effective

  machine_type      = each.value.machine_type
  image             = each.value.image
  internal_ip       = each.value.internal_ip
  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type
  assign_public_ip  = each.value.assign_public_ip
  labels            = each.value.metadata

  depends_on = [google_project_service.required, terraform_data.configuration]
}

resource "google_project_iam_member" "ops_agent_log_writer" {
  for_each = module.vm

  project = module.config.cloud_config.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${each.value.service_account_email}"
}

resource "google_project_iam_member" "ops_agent_metric_writer" {
  for_each = module.vm

  project = module.config.cloud_config.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${each.value.service_account_email}"
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

module "observability" {
  source = "./observability"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid &&
    try(module.config.config.observability.enabled, false)
  ) ? 1 : 0

  project_id      = module.config.cloud_config.project_id
  resource_prefix = module.config.resource_prefix
  alert_email     = module.config.config.observability.alert_email
  synthetic_url   = module.config.config.observability.synthetic_url
  instances = {
    for name, vm in module.vm : name => {
      instance_id = vm.instance_id
      zone        = module.config.location.zone
    }
  }

  depends_on = [google_project_service.required]
}
