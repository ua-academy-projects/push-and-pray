variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "network" {
  description = "Subnet and security group IDs created by aws_network."
  type = object({
    management_subnet_id       = string
    vm_subnet_id               = string
    security_group_ids_by_role = map(string)
  })
}

variable "instance_profile_names" {
  description = "Instance profile names from aws_basic, keyed by VM name."
  type        = map(string)
}
