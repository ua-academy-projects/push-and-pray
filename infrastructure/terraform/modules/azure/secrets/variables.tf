variable "config" { type = any }
variable "has_selected_vms" { type = bool }
variable "selected_vms" { type = any }
variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "principal_ids" {
  type = map(string)
}

variable "azure_secret_version_managers" {
  type    = list(string)
  default = []
}