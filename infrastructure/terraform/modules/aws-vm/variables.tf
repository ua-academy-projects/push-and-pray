variable "resource_prefix" {
  description = "Prefix used for AWS VM resources."
  type        = string
}

variable "vm_name" {
  description = "Logical VM name."
  type        = string
}

variable "vm" {
  description = "Provider-independent configuration for this VM."
  type        = any
}

variable "vm_defaults" {
  description = "Default VM configuration."
  type        = any
}

variable "provider_mappings" {
  description = "Provider mappings for abstract VM configuration."
  type        = any
}

variable "common_tags" {
  description = "Common tags applied to AWS resources."
  type        = map(string)
}

variable "key_name" {
  description = "EC2 key pair used for initial Ansible SSH access."
  type        = string
}

variable "management_subnet_id" {
  description = "ID of the management subnet."
  type        = string
}

variable "workload_subnet_id" {
  description = "ID of the workload subnet."
  type        = string
}

variable "security_group_ids_by_role" {
  description = "AWS security group IDs keyed by VM role."
  type        = map(string)
}

check "provider_mappings" {
  assert {
    condition = (
      can(var.provider_mappings.instance_types[local.vm.size].aws.instance_type) &&
      can(var.provider_mappings.disk_types[local.vm.disk_type].aws) &&
      can(var.provider_mappings.images[local.vm.image].aws.ssm_parameter)
    )
    error_message = "The VM size, disk type, and image must have AWS provider mappings."
  }
}
