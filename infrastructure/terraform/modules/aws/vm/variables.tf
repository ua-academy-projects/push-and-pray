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

variable "bastion_ssh_port" {
  description = "SSH port configured on the bastion before it accepts public connections."
  type        = number
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

variable "secret_arns_by_vm" {
  description = "AWS Secrets Manager ARNs each workload instance role may read, keyed by VM name."
  type        = map(list(string))
  default     = {}
}

variable "secret_ids_by_vm" {
  description = "Non-secret secret IDs each workload may read, keyed by VM name. Used only for stable Terraform resource addresses."
  type        = map(list(string))
  default     = {}
}
