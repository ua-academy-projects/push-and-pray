variable "config" {
    type = any
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

variable "instance_profile_names" {
    description = "Instance profile name per VM key, from the iam module."
    type        = map(string)
}

variable "allocation_ids" {
    description = "EIP allocation ID per VM key with assign_public_ip = true, from the addresses module."
    type        = map(string)
}

variable "public_ips" {
    description = "EIP public IP address per VM key with assign_public_ip = true, from the addresses module."
    type        = map(string)
}
