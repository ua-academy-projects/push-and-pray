terraform {
  required_version = "~> 1.15.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.6"
    }
    # The database is created with a throwaway administrator password that
    # never reaches the state; Ansible sets the real one afterwards.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    # Key Vault data-plane roles take a while to reach the vault after they
    # are assigned; the first secret write waits for them.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
