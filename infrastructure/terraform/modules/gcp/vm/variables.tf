variable "vms" {
  description = "Full VM map from project config, unfiltered."
  type        = any
}

variable "default_cloud" {
  type = string
}

variable "default_image" {
  type = string
}

variable "machine_types" {
  description = "Raw machine_types dictionary from project config."
  type        = any
}

variable "disk_types" {
  type = any
}

variable "images" {
  type = any
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "management_subnet_id" {
  type = string
}

variable "workload_subnet_id" {
  type = string
}

variable "registry_repository" {
  description = "Non-secret container registry repository used by deployment automation."
  type        = string

  validation {
    condition = (
      length(trimspace(var.registry_repository)) > 0 &&
      !can(regex("\\s", var.registry_repository))
    )
    error_message = "registry_repository must be non-empty and contain no whitespace."
  }
}

variable "image_sha" {
  description = "Immutable 40-character Git commit SHA used as the application image tag."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_sha))
    error_message = "image_sha must be a 40-character lowercase hexadecimal Git commit SHA."
  }
}

variable "docker_version" {
  description = "Exact Docker Engine apt version pinned by the cloud-init bootstrap. Verify with `apt-cache madison docker-ce` before bumping."
  type        = string
  default     = "5:29.7.2-1~ubuntu.26.04~resolute"
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}

variable "common_labels" {
  description = "Raw common_labels from project config, merged with derived base labels inside this module."
  type        = map(string)
}
