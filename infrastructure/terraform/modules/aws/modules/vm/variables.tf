variable "name" {
  description = "Name used for the instance and its IAM role."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "subnet_id" {
  description = "ID of the subnet where the instance is created."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups the instance belongs to. The AWS counterpart of the GCP network tags."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0 && length(var.security_group_ids) == length(distinct(var.security_group_ids))
    error_message = "security_group_ids must contain at least one unique group."
  }
}

variable "role" {
  description = "Functional role of the workload, independent from its resource name."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "ami" {
  description = "AMI the instance boots from. Region-scoped, so it comes from the cloud profile of this region."
  type        = string
}

variable "private_ip" {
  description = "Static private IPv4 address assigned to the instance."
  type        = string

  validation {
    condition     = can(cidrhost("${var.private_ip}/32", 0))
    error_message = "private_ip must be a valid IPv4 address."
  }
}

variable "boot_disk_size_gb" {
  description = "Size of the root volume in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "EBS volume type used by the root volume."
  type        = string

  validation {
    condition = contains([
      "standard",
      "gp2",
      "gp3",
      "io1",
      "io2",
    ], var.boot_disk_type)

    error_message = "boot_disk_type must be standard, gp2, gp3, io1, or io2."
  }
}

variable "assign_public_ip" {
  description = "Whether to create and associate a static Elastic IP."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}
