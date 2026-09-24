terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.62.0"
    }

    # AzureRM 4.81 lacks performanceCountersOTel and PromQLCriteria support.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}
