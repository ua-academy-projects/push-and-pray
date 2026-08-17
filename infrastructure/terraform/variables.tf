variable "project_id" {
  description = "Google Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid lowercase GCP project ID between 6 and 30 characters."
  }
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-east1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region, for example europe-central2."
  }
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "us-east1-b"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone must belong to the selected region."
  }
}

variable "name_prefix" {
  description = "Prefix used for GCP resource names"
  type        = string
  default     = "oilscope"

  validation {
    condition     = length(var.name_prefix) <= 17 && can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must be at most 17 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "common_labels" {
  description = "Additional labels applied to managed GCP resources"
  type        = map(string)
  default     = {}
}

variable "network_name" {
  description = "Name of the custom-mode VPC network"
  type        = string
  default     = "oilscope-vpc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.network_name))
    error_message = "network_name must be a valid GCP resource name between 2 and 63 characters."
  }
}

variable "subnet_name" {
  description = "Name of the regional application subnet"
  type        = string
  default     = "oilscope-subnet"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.subnet_name))
    error_message = "subnet_name must be a valid GCP resource name between 2 and 63 characters."
  }
}

variable "subnet_cidr" {
  description = "Primary IPv4 CIDR range for the application subnet"
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid IPv4 CIDR range."
  }
}

variable "router_name" {
  description = "Name of the Cloud Router used by Cloud NAT"
  type        = string
  default     = "oilscope-router"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.router_name))
    error_message = "router_name must be a valid GCP resource name between 2 and 63 characters."
  }
}

variable "nat_name" {
  description = "Name of the Cloud NAT gateway"
  type        = string
  default     = "oilscope-nat"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.nat_name))
    error_message = "nat_name must be a valid GCP resource name between 2 and 63 characters."
  }
}

variable "internal_addresses" {
  description = "Reserved internal IPv4 addresses for the future application VMs"
  type        = map(string)
  default = {
    fetcher = "10.10.0.10"
    history = "10.10.0.11"
    infra   = "10.10.0.12"
    ui      = "10.10.0.14"
  }

  validation {
    condition = (
      length(setsubtract(toset(keys(var.internal_addresses)), toset(["fetcher", "history", "infra", "ui"]))) == 0 &&
      length(keys(var.internal_addresses)) == 4 &&
      length(distinct(values(var.internal_addresses))) == 4 &&
      alltrue([for address in values(var.internal_addresses) : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", address))])
    )
    error_message = "internal_addresses must contain unique IPv4 addresses for fetcher, history, infra, and ui."
  }
}

variable "machine_types" {
  description = "Compute Engine machine types keyed by VM role"
  type        = map(string)
  default = {
    infra   = "e2-small"
    history = "e2-micro"
    fetcher = "e2-micro"
    ui      = "e2-micro"
  }

  validation {
    condition = (
      length(setsubtract(toset(keys(var.machine_types)), toset(["fetcher", "history", "infra", "ui"]))) == 0 &&
      length(keys(var.machine_types)) == 4 &&
      alltrue([for machine_type in values(var.machine_types) : length(trimspace(machine_type)) > 0])
    )
    error_message = "machine_types must contain non-empty values for fetcher, history, infra, and ui."
  }
}

variable "boot_image_project" {
  description = "Project that publishes the Compute Engine boot image family"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "boot_image_family" {
  description = "Compute Engine boot image family used by all application VMs"
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB for each application VM"
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "Persistent disk type used for VM boot disks"
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be one of: pd-standard, pd-balanced, pd-ssd."
  }
}

variable "infra_data_disk_size_gb" {
  description = "Size in GiB of the persistent data disk attached to the Infra VM"
  type        = number
  default     = 30

  validation {
    condition     = var.infra_data_disk_size_gb >= 10
    error_message = "infra_data_disk_size_gb must be at least 10 GiB."
  }
}

variable "infra_data_disk_type" {
  description = "Persistent disk type used for Infra application data"
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.infra_data_disk_type)
    error_message = "infra_data_disk_type must be one of: pd-standard, pd-balanced, pd-ssd."
  }
}

variable "app_domain" {
  description = "Public DNS name that will later route to Traefik on the UI VM"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", var.app_domain))
    error_message = "app_domain must be a lowercase fully qualified DNS name."
  }
}

variable "acme_email" {
  description = "Email address that Traefik will later use for ACME registration"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.acme_email))
    error_message = "acme_email must be a valid email address."
  }
}

variable "ghcr_owner" {
  description = "GitHub organization or user that owns the private GHCR application images"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.ghcr_owner))
    error_message = "ghcr_owner must be a valid GitHub organization or username."
  }
}

variable "fetcher_image_tag" {
  description = "Immutable full commit SHA tag for the Fetcher GHCR image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.fetcher_image_tag))
    error_message = "fetcher_image_tag must be a lowercase 40-character commit SHA."
  }
}

variable "history_image_tag" {
  description = "Immutable full commit SHA tag for the History GHCR image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.history_image_tag))
    error_message = "history_image_tag must be a lowercase 40-character commit SHA."
  }
}

variable "ui_image_tag" {
  description = "Immutable full commit SHA tag for the UI GHCR image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.ui_image_tag))
    error_message = "ui_image_tag must be a lowercase 40-character commit SHA."
  }
}
