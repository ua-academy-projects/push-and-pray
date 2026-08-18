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
    condition     = length(var.name_prefix) <= 16 && can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must be at most 16 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
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

variable "management_subnet_cidr" {
  description = "CIDR of the management subnet used by the bastion."
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "workload_subnet_cidr" {
  description = "CIDR of the workload subnet used by all application VMs."
  type        = string
  default     = "10.10.1.0/24"

  validation {
    condition     = can(cidrhost(var.workload_subnet_cidr, 0))
    error_message = "workload_subnet_cidr must be a valid IPv4 CIDR block."
  }

}

variable "ssh_port" {
  description = "Team-approved non-default SSH port. Used by the firewall rules and by sshd on the bastion."
  type        = number
  default     = 18832

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535 && var.ssh_port != 22
    error_message = "ssh_port must be in the 1024-65535 range and must not be the default port 22."
  }
}

variable "bastion_allowed_cidrs" {
  description = "Source CIDRs allowed to reach the bastion on ssh_port. Office ranges / VPN egress IPs only, never 0.0.0.0/0."
  type        = list(string)
}

variable "ssh_users" {
  description = <<-EOT
    One PUBLIC SSH key per person, keyed by the Linux username.
    Private keys are never generated, accepted or stored by this configuration.
  EOT
  type        = map(string)
}

variable "machine_types" {
  description = "Compute Engine machine types keyed by workload role."
  type        = map(string)
  default = {
    infra   = "e2-micro"
    history = "e2-micro"
    fetcher = "e2-micro"
    ui      = "e2-micro"
  }

  validation {
    condition = (
      length(keys(var.machine_types)) == 4 &&
      length(setsubtract(toset(keys(var.machine_types)), toset(["infra", "history", "fetcher", "ui"]))) == 0 &&
      alltrue([for machine_type in values(var.machine_types) : length(trimspace(machine_type)) > 0])
    )
    error_message = "machine_types must contain non-empty values for infra, history, fetcher and ui."
  }
}

variable "internal_addresses" {
  description = "Static workload IPv4 addresses in the workload subnet."
  type        = map(string)
  default = {
    infra   = "10.10.1.12"
    history = "10.10.1.11"
    fetcher = "10.10.1.10"
    ui      = "10.10.1.14"
  }

  validation {
    condition = (
      length(keys(var.internal_addresses)) == 4 &&
      length(setsubtract(toset(keys(var.internal_addresses)), toset(["infra", "history", "fetcher", "ui"]))) == 0 &&
      length(distinct(values(var.internal_addresses))) == 4 &&
      alltrue([for address in values(var.internal_addresses) : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", address))])
    )
    error_message = "internal_addresses must contain unique IPv4 addresses for infra, history, fetcher and ui."
  }
}

variable "boot_image_project" {
  description = "Project that publishes the workload boot image family."
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "boot_image_family" {
  description = "Boot image family used by workload VMs."
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB for workload VMs."
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "Persistent-disk type used for workload boot disks."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be pd-standard, pd-balanced or pd-ssd."
  }
}
