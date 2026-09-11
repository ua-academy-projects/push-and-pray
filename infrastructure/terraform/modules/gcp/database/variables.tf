variable "project_id" { type = string }
variable "resource_prefix" { type = string }
variable "region" { type = string }
variable "generation" { type = string }
variable "engine_version" { type = string }
variable "database_name" { type = string }
variable "username" { type = string }
variable "password" {
  type      = string
  sensitive = true
  nullable  = false
}
variable "tier" { type = string }
variable "disk_size_gb" { type = number }
variable "availability_type" { type = string }
variable "private_service_cidr" { type = string }
variable "network_id" { type = string }
variable "backup_on_delete" { type = bool }
variable "backups_enabled" { type = bool }
variable "deletion_protection" { type = bool }
variable "backup_run_id" {
  type     = number
  default  = null
  nullable = true
}
variable "labels" { type = map(string) }
