variable "resource_prefix" { type = string }
variable "generation" { type = string }
variable "engine_version" { type = string }
variable "database_name" { type = string }
variable "username" { type = string }
variable "password" {
  type      = string
  sensitive = true
  nullable  = false
}
variable "port" { type = number }
variable "instance_class" { type = string }
variable "allocated_storage_gb" { type = number }
variable "multi_az" { type = bool }
variable "backup_on_delete" { type = bool }
variable "backups_enabled" { type = bool }
variable "deletion_protection" { type = bool }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "workload_security_group_ids" { type = map(string) }
variable "remote_workload_cidrs" {
  type    = set(string)
  default = []
}
variable "snapshot_identifier" {
  type     = string
  default  = null
  nullable = true
}
variable "tags" { type = map(string) }
