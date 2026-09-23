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

variable "delegated_subnet_id" {
  type    = string
  default = null
}

variable "vnet_id" {
  type    = string
  default = null
}

variable "key_vault_id" {
  type    = string
  default = null
}

variable "postgres_password_secret_id" {
  type    = string
  default = null
}
