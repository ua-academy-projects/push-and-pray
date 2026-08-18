variable "project_id" {
  description = "GCP project ID where all resources are created."
  type        = string
}

variable "region" {
  description = "Region of the bastion's static external IP. Must be the region of the subnet the bastion is placed in."
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "Zone for the bastion host. Must belong to var.region."
  type        = string
  default     = "europe-central2-a"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone must belong to the selected region, for example europe-central2-a for region europe-central2."
  }
}

variable "name_prefix" {
  description = "Prefix for every resource name. Keep it short: GCP names are limited to 63 chars."
  type        = string
  default     = "oil"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels applied to every resource that supports them."
  type        = map(string)
  default     = {}
}

variable "bastion_machine_type" {
  description = "Machine type for the bastion. It only forwards SSH, so keep it tiny."
  type        = string
  default     = "e2-micro"
}

variable "bastion_image" {
  description = "Boot image for the bastion."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "bastion_disk_size_gb" {
  description = "Bastion boot disk size in GB."
  type        = number
  default     = 20
}

variable "bastion_preemptible" {
  description = "Run the bastion as a Spot VM. Cheaper, but it can be reclaimed at any time."
  type        = bool
  default     = false
}

variable "grant_bastion_logging_roles" {
  description = "Grant the bastion service account roles/logging.logWriter and roles/monitoring.metricWriter so SSH sessions are auditable."
  type        = bool
  default     = true
}

variable "ssh_port" {
  description = "Non-default SSH port. Must match the ssh_port of the network module, whose firewall rule opens it."
  type        = number
  default     = 18832

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535 && var.ssh_port != 22
    error_message = "ssh_port must be in the 1024-65535 range and must not be the default port 22."
  }
}

variable "subnetwork_id" {
  description = "ID of the subnet to place the bastion in. Pass module.network.public_subnet.id."
  type        = string
}

variable "network_tag" {
  description = "Network tag the network module's firewall rules expect on the bastion. Pass module.network.network_tags.bastion."
  type        = string
}

variable "ssh_users" {
  description = <<-EOT
    One public SSH key per person, keyed by the Linux username.
    Values are PUBLIC keys only (ssh-ed25519 / ssh-rsa / ecdsa-* / sk-*).
    Private keys are never accepted, never generated and never stored by this module.

    Example:
      ssh_users = {
        tabula = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... tabula@laptop"
        rasa   = file("~/keys/rasa.pub")
      }
  EOT
  type        = map(string)

  validation {
    condition     = length(var.ssh_users) > 0
    error_message = "At least one person must be granted access: a bastion nobody can log into is useless."
  }

  validation {
    condition = alltrue([
      for u in keys(var.ssh_users) : can(regex("^[a-z_][a-z0-9_-]{0,31}$", u))
    ])
    error_message = "Every ssh_users key must be a valid POSIX username (lowercase, starts with a letter or underscore, max 32 chars)."
  }

  validation {
    condition = alltrue([
      for k in values(var.ssh_users) :
      can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) AAAA[0-9A-Za-z+/=]+", trimspace(k)))
    ])
    error_message = "Every ssh_users value must be a single OpenSSH PUBLIC key line starting with a supported key type."
  }

  validation {
    condition = alltrue([
      for k in values(var.ssh_users) :
      !can(regex("(?i)PRIVATE KEY", k))
    ])
    error_message = "A PRIVATE key was passed to ssh_users. Private keys must never enter Terraform code or state - pass the .pub file only."
  }

  validation {
    condition = alltrue([
      for k in values(var.ssh_users) : length(split("\n", trimspace(k))) == 1
    ])
    error_message = "Exactly one public key per person is supported: each ssh_users value must be a single line."
  }
}
