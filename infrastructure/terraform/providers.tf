provider "google" {
  project = try(local.config.project_id, null)
  region  = local.config.regions[local.config.region].gcp.region
  zone    = local.config.regions[local.config.region].gcp.zone
}
provider "aws" {
  region = local.config.regions[local.config.region].aws.region
}
provider "cloudflare" {
  api_token = coalesce(var.cloudflare_api_token, "0000000000000000000000000000000000000000")
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = try(local.config.azure_subscription_id, "00000000-0000-0000-0000-000000000000")
}