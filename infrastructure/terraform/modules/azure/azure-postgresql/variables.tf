variable "enabled" {
  type = bool
}

variable "clients_share_cloud" {
  type = bool
}

variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type     = string
  nullable = true
}

variable "location" {
  type     = string
  nullable = true
}

variable "zone" {
  type     = string
  nullable = true
}

variable "virtual_network_ids" {
  type    = map(string)
  default = {}
}

variable "delegated_subnet_id" {
  type     = string
  nullable = true
}

variable "identity_principal_ids" {
  type    = map(string)
  default = {}
}

variable "database_version" {
  type = string
}

variable "sku_name" {
  type = string
}

variable "storage_mb" {
  type = number
}

variable "backup_retention_days" {
  type = number
}

variable "database_name" {
  type = string
}

variable "username" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
