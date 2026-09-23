variable "config" { type = any }
variable "selected_vms" { type = any }
variable "management_subnet_id" { type = string }
variable "workload_subnet_id" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "identity_ids" {
  type = map(string)
}