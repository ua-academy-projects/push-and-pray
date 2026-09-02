variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "key_names_by_location" {
  description = "EC2 key-pair names keyed by abstract location."
  type        = map(string)
}

variable "management_subnet_ids" {
  description = "Management subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "workload_subnet_ids" {
  description = "Workload subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "security_group_ids_by_location" {
  description = "AWS security-group IDs keyed by abstract location and VM role."
  type        = map(map(string))
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
