# Provider configuration has to live in the root module, so this is the one
# place outside modules/<cloud> that names a provider.

locals {
  aws_in_use = length([
    for name, vm in local.config.vms : name
    if try(vm.cloud, local.config.default_cloud) == "aws"
  ]) > 0
}

provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = try(local.config.clouds.gcp.region, null)
  zone    = try(local.config.clouds.gcp.zone, null)
}

provider "aws" {
  region = try(local.config.clouds.aws.region, "us-east-1")
  access_key                  = local.aws_in_use ? null : "unused"
  secret_key                  = local.aws_in_use ? null : "unused"
  skip_credentials_validation = !local.aws_in_use
  skip_requesting_account_id  = !local.aws_in_use
  skip_metadata_api_check     = !local.aws_in_use
}
