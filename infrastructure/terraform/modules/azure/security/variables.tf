variable "config" {
  type = any
}

variable "has_selected_vms" {
  type = bool
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "selected_vms" {
  type = any
}

variable "management_subnet_id" {
  type = string
}

variable "workload_subnet_id" {
  type = string
}