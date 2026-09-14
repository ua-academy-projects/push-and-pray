variable "project_id" { type = string }
variable "region" { type = string }
variable "resource_prefix" { type = string }
variable "network_id" { type = string }
variable "database_name" { type = string }
variable "database_user" { type = string }
variable "password" {
  type      = string
  sensitive = true
}
variable "labels" { type = map(string) }
