variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "private_route_table_id" { type = string }
variable "availability_zones" {
  type = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(toset(var.availability_zones)) >= 2
    error_message = "availability_zones must contain at least two distinct Availability Zones."
  }
}
variable "application_sg_ids" { type = map(string) }
variable "database_name" { type = string }
variable "database_user" { type = string }
variable "database_port" { type = number }
variable "password" {
  type      = string
  sensitive = true
}
variable "tags" { type = map(string) }
