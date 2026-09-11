locals {
  root_config = jsondecode(file(var.project_config_path))
  used_clouds = toset([
    for vm in values(local.root_config.vms) :
    lower(lookup(vm, "cloud", local.root_config.default_cloud))
  ])
  gcp_enabled = contains(local.used_clouds, "gcp")
  aws_enabled = contains(local.used_clouds, "aws")
  mixed_cloud = local.aws_enabled && local.gcp_enabled
  mixed_network_enabled = (
    local.mixed_cloud && try(local.root_config.mixed_network.enabled, false)
  )
  manage_db = try(local.root_config.manage_db, false)
  database_vm_count = length([
    for vm in values(local.root_config.vms) : vm
    if vm.role == "database"
  ])
}

provider "google" {
  project = try(local.root_config.clouds.gcp.project_id, null)
  region  = try(local.root_config.clouds.gcp.locations[local.root_config.defaults.location_profile].region, null)
  zone    = try(local.root_config.clouds.gcp.locations[local.root_config.defaults.location_profile].zone, null)

  access_token = local.gcp_enabled ? null : "provider-not-used"
}

provider "aws" {
  region = try(local.root_config.clouds.aws.locations[local.root_config.defaults.location_profile].region, null)

  access_key = local.aws_enabled ? null : "provider-not-used"
  secret_key = local.aws_enabled ? null : "provider-not-used"

  skip_credentials_validation = !local.aws_enabled
  skip_metadata_api_check     = !local.aws_enabled
  skip_requesting_account_id  = !local.aws_enabled
}
