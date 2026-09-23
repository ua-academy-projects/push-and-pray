variable "config" { type = any }
variable "selected_vms" { type = any }
variable "has_selected_vms" { type = bool }
variable "instance_ids" { type = map(string) }
variable "resource_group_id" { type = string }
variable "resource_group_name" { type = string }