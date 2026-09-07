provider "google" {
  project = local.gcp_project_id
  region  = local.gcp_region
  zone    = local.gcp_zone
}

provider "aws" {
  region = local.aws_region

  # Terraform initializes declared providers even when their resource collections
  # are empty. Only the no-AWS path bypasses authentication; active AWS VMs use
  # the normal credential chain. All AWS resources are gated by these placements.
  access_key = length(local.aws_placements) == 0 ? "mock_access_key" : null
  secret_key = length(local.aws_placements) == 0 ? "mock_secret_key" : null

  skip_credentials_validation = length(local.aws_placements) == 0
  skip_metadata_api_check     = length(local.aws_placements) == 0
  skip_requesting_account_id  = length(local.aws_placements) == 0
  skip_region_validation      = length(local.aws_placements) == 0
}
