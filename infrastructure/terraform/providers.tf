provider "google" {
  project = local.gcp_project_id
  region  = local.gcp_region
  zone    = local.gcp_zone
}

provider "aws" {
  region = local.aws_region
}
