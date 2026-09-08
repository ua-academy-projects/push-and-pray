variable "vms" {
  description = "Resolved GCP VM definitions keyed by logical VM name."
  type = map(object({
    role             = string
    effective_cloud  = string
    instance_type    = string
    internal_ip      = string
    assign_public_ip = bool
    disk_type        = string
    location = object({
      region = string
      zone   = string
    })
    image_config = object({
      reference = string
    })
    boot_disk = object({
      size_gb = number
    })
    network_tags = list(string)
    labels       = optional(map(string), {})
  }))
}

variable "resource_prefix" {
  description = "Prefix used to construct VM and service-account names."
  type        = string
}

variable "common_labels" {
  description = "Labels shared by all VM-related resources."
  type        = map(string)
}

variable "management_subnet_id" {
  description = "Subnet assigned to the bastion VM."
  type        = string
}

variable "workload_subnet_id" {
  description = "Subnet assigned to non-bastion VM workloads."
  type        = string
}

variable "ssh_users" {
  description = "Operator public SSH keys keyed by Linux username."
  type        = map(string)
}
