provider "google" {
  project = try(jsondecode(file(var.project_config_path)).clouds.gcp.project_id, null)
  region  = try(jsondecode(file(var.project_config_path)).clouds.gcp.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].region, null)
  zone    = try(jsondecode(file(var.project_config_path)).clouds.gcp.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].zone, null)
}

provider "aws" {
  region = try(jsondecode(file(var.project_config_path)).clouds.aws.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].region, null)
}
