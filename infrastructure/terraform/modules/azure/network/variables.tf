variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "resource_prefix" { type = string }
variable "tags" { type = map(string) }
variable "vpc_cidr" { type = string }
variable "management_subnet_cidr" { type = string }
variable "workload_subnet_cidr" { type = string }
variable "managed_database_subnet_cidr" { type = string }
variable "managed_database_enabled" {
  type    = bool
  default = false
}
