terraform {
  required_version = "~> 1.15.1"

  # Initialize with a GCS prefix distinct from the existing K3s root state.
  backend "gcs" {
    prefix = "terraform/managed-kubernetes"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.62"
    }
  }
}

provider "azurerm" {
  features {}
}
