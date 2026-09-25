terraform {
  required_version = "~> 1.16.0"

  backend "local" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.20"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
