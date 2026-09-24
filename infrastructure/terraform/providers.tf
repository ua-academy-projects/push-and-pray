provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = local.config.region_map[local.config.region]["gcp"].region
  zone    = local.config.region_map[local.config.region]["gcp"].zone
}

provider "aws" {
  region = local.config.region_map[local.config.region]["aws"].region
}

# Credentials come from the environment or `az login`, never from the project
# configuration. Unlike the other two providers, azurerm configures itself for
# every plan in this root even when the configuration selects no Azure
# resource, so a subscription has to be resolvable: from clouds.azure here, or
# from ARM_SUBSCRIPTION_ID for an AWS or GCP deployment. See README.md.
provider "azurerm" {
  subscription_id = try(local.config.clouds.azure.subscription_id, null)

  # Register exactly the services this project uses, rather than letting the
  # provider register a wider default set on the operator's behalf. Registration
  # is a subscription-level write: pre-register these and the operator needs no
  # such permission.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
  ]

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    key_vault {
      # A vault name stays reserved for its soft-delete retention; recovering it
      # is deliberate, purging it is not.
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = false
    }
  }
}

# Credentials come from CLOUDFLARE_API_TOKEN, never from the project
# configuration. With cloudflare.enabled = false nothing here is configured,
# so a deployment that manages its DNS by hand needs no token at all.
provider "cloudflare" {}