provider "google" {
  project = jsondecode(file(var.project_config_path)).clouds.gcp.project_id
  region  = jsondecode(file(var.project_config_path)).clouds.gcp.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].region
  zone    = jsondecode(file(var.project_config_path)).clouds.gcp.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].zone
}

provider "aws" {
  region = jsondecode(file(var.project_config_path)).clouds.aws.locations[jsondecode(file(var.project_config_path)).defaults.location_profile].region
}
