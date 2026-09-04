locals {
  module_cloud = "gcp"
  config       = jsondecode(file(var.project_config_path))
  cloud_config = lookup(local.config.clouds, local.module_cloud, {})
  defaults     = local.config.defaults

  selected_vms = {
    for name, vm in local.config.vms : name => vm
    if lower(lookup(vm, "cloud", local.config.default_cloud)) == local.module_cloud
  }

  effective_vms = {
    for name, vm in local.selected_vms : name => merge(vm, {
      machine_type = lookup(
        lookup(local.cloud_config, "machine_types", {}),
        lookup(vm, "machine_profile", local.defaults.machine_profile),
        null,
      )
      image = lookup(
        lookup(local.cloud_config, "images", {}),
        lookup(vm, "image_profile", local.defaults.image_profile),
        null,
      )
      disk_type = lookup(
        lookup(local.cloud_config, "disk_types", {}),
        lookup(vm.boot_disk, "profile", local.defaults.disk_profile),
        null,
      )
    })
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"
  common_labels = merge(
    lookup(local.config, "common_labels", {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.module_cloud
    }
  )

  bastions = {
    for name, vm in local.effective_vms : name => vm
    if vm.role == "bastion"
  }
  bastion = try(values(local.bastions)[0], null)

  workload_vms = {
    for name, vm in local.effective_vms : name => vm
    if(
      vm.role != "bastion" &&
      vm.machine_type != null &&
      vm.image != null &&
      vm.disk_type != null
    )
  }

  required_apis = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, workload in local.workload_vms : [
      for secret_id in distinct(values(workload.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(local.all_secret_ids), var.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}

resource "terraform_data" "configuration" {
  count = length(local.selected_vms) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.bastions) <= 1
      error_message = "GCP may contain at most one VM with role bastion."
    }
  }
}

resource "google_project_service" "required" {
  for_each = length(local.selected_vms) > 0 ? local.required_apis : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

module "network" {
  source = "../network"
  count  = length(local.selected_vms) > 0 ? 1 : 0

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr
  ui_public_ports        = [for port in local.config.network.ui_public_ports : tostring(port)]

  enable_bastion               = local.bastion != null
  bastion_ssh_port             = try(local.bastion.ssh_port, 22)
  bastion_allowed_cidrs        = try(local.bastion.allowed_cidrs, [])
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  history_api_port             = local.config.service_ports.history_api
  postgresql_port              = local.config.service_ports.postgresql

  depends_on = [google_project_service.required, terraform_data.configuration]
}

# trivy:ignore:AVD-GCP-0031 Public IPs are restricted to UI and bastion by module validation.
module "vm" {
  source = "../vm"
  for_each = {
    for name, vm in local.effective_vms : name => vm
    if vm.machine_type != null && vm.image != null && vm.disk_type != null
  }

  name          = "${local.resource_prefix}-${each.key}"
  subnetwork_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : module.network[0].workload_subnet_id
  role          = each.value.role

  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  ssh_users           = local.config.ssh_users
  network_tags = [
    for tag in each.value.network_tags : "${local.resource_prefix}-${tag}"
  ]

  machine_type      = each.value.machine_type
  image             = each.value.image
  internal_ip       = each.value.internal_ip
  ssh_port          = lookup(each.value, "ssh_port", 22)
  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type
  assign_public_ip  = each.value.assign_public_ip

  labels = merge(
    local.common_labels,
    lookup(each.value, "labels", {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.module_cloud
      role        = each.value.role
      vm_name     = each.key
    },
  )

  depends_on = [google_project_service.required, terraform_data.configuration]
}

resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.all_secret_ids)
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in local.workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.vm[each.value.vm_name].service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
