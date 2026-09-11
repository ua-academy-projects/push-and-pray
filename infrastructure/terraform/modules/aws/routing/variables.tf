variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "management_subnet_id" { type = string }
variable "workload_subnet_id" { type = string }
variable "public_subnet_id" { type = string }
variable "enable_bastion_nat" { type = bool }
variable "bastion_network_interface_id" {
  type     = string
  nullable = true
}
variable "tags" { type = map(string) }
