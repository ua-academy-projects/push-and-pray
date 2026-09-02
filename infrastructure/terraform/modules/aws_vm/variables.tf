variable "name" {
  description = "Name of the EC2 instance and related AWS resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "role" {
  description = "Functional role of the VM."
  type        = string

  validation {
    condition = contains([
      "bastion",
      "database",
      "history",
      "fetcher",
      "ui",
    ], var.role)

    error_message = "role must be bastion, database, history, fetcher, or ui."
  }
}

variable "subnet_id" {
  description = "AWS subnet ID where the EC2 instance is created."
  type        = string
}

variable "security_group_id" {
  description = "Security group assigned to the EC2 instance."
  type        = string
}

variable "instance_type" {
  description = "Resolved AWS EC2 instance type."
  type        = string
}

variable "image_owners" {
  description = "AWS account IDs allowed to own the selected AMI."
  type        = list(string)

  validation {
    condition = (
      length(var.image_owners) > 0 &&
      alltrue([
        for owner in var.image_owners :
        can(regex("^[0-9]{12}$", owner))
      ])
    )

    error_message = "image_owners must contain at least one valid 12-digit AWS account ID."
  }
}

variable "image_name_pattern" {
  description = "Name pattern used to locate the Ubuntu AMI."
  type        = string
}

variable "private_ip" {
  description = "Static private IPv4 address. Null lets AWS choose an address from the subnet."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.private_ip == null ||
      can(cidrhost("${var.private_ip}/32", 0))
    )

    error_message = "private_ip must be null or a valid IPv4 address."
  }
}

variable "boot_disk_size_gb" {
  description = "Size of the EC2 root EBS volume in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 8
    error_message = "boot_disk_size_gb must be at least 8 GiB."
  }
}

variable "boot_disk_type" {
  description = "Resolved AWS EBS volume type."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to allocate and associate an Elastic IP."
  type        = bool
  default     = false
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

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
