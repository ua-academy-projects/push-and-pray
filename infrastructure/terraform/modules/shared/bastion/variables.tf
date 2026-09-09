variable "config" {
  description = "The parts of the project configuration this module reads. A wider object converts down to this type, so the caller passes the whole configuration."
  type = object({
    bastion = object({
      ssh_port      = number
      allowed_cidrs = list(string)
      size          = optional(string, "tiny")
      image         = optional(string, "ubuntu-lts")
      boot_disk = optional(object({
        size_gb = optional(number, 10)
        type    = optional(string, "balanced")
      }), {})
    })
  })
}

variable "cloud" {
  description = "Which cloud this bastion is being built on. The caller's own name for itself."
  type        = string
  nullable    = false
}

variable "profile" {
  description = "That cloud's profile. The lookup maps translate the bastion's abstract labels, and subnets.management gives the range its address is taken from."
  type = object({
    subnets = object({
      management = string
    })
    machine_sizes = map(string)
    disk_types    = map(string)
    images        = map(string)
  })

  validation {
    condition     = contains(keys(var.profile.machine_sizes), var.config.bastion.size)
    error_message = "The bastion size label must exist in this cloud's machine_sizes."
  }

  validation {
    condition     = contains(keys(var.profile.images), var.config.bastion.image)
    error_message = "The bastion image label must exist in this cloud's images."
  }

  validation {
    condition     = contains(keys(var.profile.disk_types), var.config.bastion.boot_disk.type)
    error_message = "The bastion boot disk label must exist in this cloud's disk_types."
  }
}

variable "host_index" {
  description = "Offset of the bastion's address inside subnets.management. Providers reserve a different number of leading addresses - GCP takes .0 and .1, AWS takes the first four - so the caller supplies the first index its provider leaves free. A number rather than a condition on the cloud name, so adding a provider adds an argument and not a branch."
  type        = number

  validation {
    condition     = var.host_index >= 0
    error_message = "host_index must not be negative."
  }
}
