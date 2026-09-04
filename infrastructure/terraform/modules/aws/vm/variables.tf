variable "vms" {
    type = any
}

variable "default_cloud" {
    type = string
}

variable "default_image" {
    type = string
}

variable "machine_types" {
    type = any
}

variable "disk_types" {
    type = any
}

variable "images" {
    type = any
}

variable "name_prefix" {
    type = string
}

variable "environment" {
    type = string
}

variable "management_subnet_id" {
    type = string
}

variable "workload_subnet_id" {
    type = string
}

variable "ssh_users" {
    type = map(string)
}

variable "security_group_ids" {
    type = map(string)
}