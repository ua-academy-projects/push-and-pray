provider "google" {
  project = local.gcp_project_id
  region  = local.region["gcp"]
  zone    = local.zone["gcp"]
}

provider "aws" {
  region = local.aws_provider_region

  default_tags {
    tags = local.common_labels
  }
}
