variable "config" {
  description = "Structured project configuration decoded once by the root module."
  type        = any
  validation {
    condition = alltrue([
      for vm in values(var.config.vms) : (
        can(var.config.cloud_mappings.regions[try(vm.region, var.config.default_region)].aws.region) &&
        can(var.config.cloud_mappings.regions[try(vm.region, var.config.default_region)].aws.zone) &&
        can(var.config.cloud_mappings.sizes[vm.size].aws) &&
        can(var.config.cloud_mappings.disk_types[vm.boot_disk.type].aws) &&
        can(var.config.cloud_mappings.images[vm.image].aws)
      ) if try(vm.cloud, var.config.default_cloud) == "aws"
    ])
    error_message = "Every AWS VM must have region, size, disk and image mappings for its provider."
  }

}

variable "resource_prefix" {
  description = "Shared deployment resource name prefix."
  type        = string
}

variable "common_labels" {
  description = "Validated cross-cutting deployment labels."
  type        = map(string)
}

variable "network" {
  description = "Existing provider network outputs; null when this provider has no VMs."
  type = object({
    management_subnet_id = string
    workload_subnet_id   = string
    security_group_ids   = map(string)
  })
}

variable "ssh_users" {
  description = "Linux operator usernames mapped to their public SSH keys."
  type        = map(string)

  validation {
    condition = length(var.ssh_users) > 0 && alltrue([
      for username, public_key in var.ssh_users :
      can(regex("^[a-z_][a-z0-9_-]{0,31}$", username)) &&
      can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/]+={0,3}( .+)?$", trimspace(public_key)))
    ])

    error_message = "ssh_users must contain at least one valid Linux username and OpenSSH public key."
  }
}

variable "startup_scripts" {
  description = "Optional non-secret bootstrap shell scripts keyed by VM configuration key."
  type        = map(string)
  default     = {}
}
