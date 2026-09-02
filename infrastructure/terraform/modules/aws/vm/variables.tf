variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "key_name" {
  description = "EC2 key pair used for initial Ansible SSH access."
  type        = string
  nullable    = true
}

variable "management_subnet_id" {
  description = "ID of the management subnet."
  type        = string
  nullable    = true
}

variable "workload_subnet_id" {
  description = "ID of the workload subnet."
  type        = string
  nullable    = true
}

variable "security_group_ids_by_role" {
  description = "AWS security group IDs keyed by VM role."
  type        = map(string)
}

check "provider_mappings" {
  assert {
    condition = alltrue([
      for vm in values(local.vms) : (
        can(var.config.provider_mappings.instance_types[vm.size].aws.instance_type) &&
        can(var.config.provider_mappings.disk_types[vm.disk_type].aws) &&
        can(var.config.provider_mappings.images[vm.image].aws.ssm_parameter) &&
        can(var.config.locations[vm.location].aws.region) &&
        can(var.config.locations[vm.location].aws.availability_zone)
      )
    ])
    error_message = "Every selected VM size, disk type, image, and location must have AWS provider mappings."
  }
}
