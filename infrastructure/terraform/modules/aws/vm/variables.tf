variable "vms" {
  type = map(object({
    role             = string
    effective_cloud  = string
    instance_type    = string
    internal_ip      = string
    assign_public_ip = bool
    disk_type        = string
    image_config = object({
      name_filter = string
      owners      = list(string)
    })
    boot_disk = object({
      size_gb = number
    })
    labels = optional(map(string), {})
  }))
}
variable "resource_prefix" {
  type = string
}

variable "common_labels" {
  type = map(string)
}

variable "key_name" {
  type = string
}

variable "management_subnet_id" {
  type = string
}

variable "workload_subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = map(string)
}
