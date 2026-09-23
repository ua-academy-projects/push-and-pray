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

variable "vnet_cidr" {
  type    = string
  default = "10.0.0.0/16"
}