provider "google" {
  project               = local.config.clouds.gcp.project_id
  region                = local.config.regions[local.config.default_region].gcp.region
  zone                  = local.config.regions[local.config.default_region].gcp.zone
  billing_project       = local.config.clouds.gcp.project_id
  user_project_override = true
}
provider "aws" {
  region = local.config.regions[local.config.default_region].aws.region
}

provider "azurerm" {
  features {}

  subscription_id                 = local.config.clouds.azure.subscription_id
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.Consumption",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]
}

provider "cloudflare" {}
