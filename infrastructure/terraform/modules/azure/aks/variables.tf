variable "config" {
  type = any
}

variable "has_selected_vms" {
  type = bool
}

variable "selected_vms" {
  type = any
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "bastion_public_ip" {
  type    = string
  default = null
}
