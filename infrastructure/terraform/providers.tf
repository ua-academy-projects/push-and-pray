# Provider configuration has to live in the root module, so this is the one
# place outside modules/<cloud> that names a provider.

locals {
  aws_in_use   = contains(local.active_clouds, "aws")
  azure_in_use = contains(local.active_clouds, "azure")
}

provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = try(local.config.clouds.gcp.region, null)
  zone    = try(local.config.clouds.gcp.zone, null)

  # A budget belongs to the billing account, not to a project, so the Budget
  # API has no project to charge the request to. With user credentials it then
  # refuses to answer unless the caller names a quota project - and the
  # provider ignores the quota_project_id in the ADC file. This names the
  # project the configuration already uses; the caller needs
  # serviceusage.services.use on it, which Owner and Editor carry.
  billing_project       = try(local.config.clouds.gcp.project_id, null)
  user_project_override = true
}

provider "aws" {
  region                      = try(local.config.clouds.aws.region, "us-east-1")
  access_key                  = local.aws_in_use ? null : "unused"
  secret_key                  = local.aws_in_use ? null : "unused"
  skip_credentials_validation = !local.aws_in_use
  skip_requesting_account_id  = !local.aws_in_use
  skip_metadata_api_check     = !local.aws_in_use
}

provider "azurerm" {
  features {}

  subscription_id = try(local.config.clouds.azure.subscription_id, null)

  resource_provider_registrations = "none"
  resource_providers_to_register = local.azure_in_use ? [
    "Microsoft.AlertsManagement",
    "Microsoft.Compute",
    "Microsoft.Consumption",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Portal",
  ] : []
}
