provider "aws" {
  # The provider is loaded even when this deployment has no AWS resources.
  region = try(local.config.locations[local.config.default_location].aws.region, "us-east-1")
}

provider "google" {
  project = try(local.config.cloud_settings.gcp.project_id, null)
}

provider "cloudflare" {}

provider "azurerm" {
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.OperationalInsights",
  ]

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      # Application Insights creates Smart Detection resources outside
      # Terraform state. The deployment resource group is dedicated to this
      # stack, so let Azure remove those children when the group is destroyed.
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = try(local.config.cloud_settings.azure.subscription_id, null)
}
