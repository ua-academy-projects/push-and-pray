variable "enabled" {
  description = "Create the Cloud SQL resources."
  type        = bool
}

variable "clients_share_cloud" {
  description = "Whether all database clients share the Cloud SQL cloud and private network."
  type        = bool
}

variable "project_id" {
  type     = string
  nullable = true
}

variable "region" {
  type     = string
  nullable = true
}

variable "name_prefix" {
  type = string
}

variable "network_id" {
  type     = string
  nullable = true
}

variable "database_version" {
  type = string
}

variable "tier" {
  type = string
}

variable "disk_size" {
  type = number
}

variable "database_name" {
  type = string
}

variable "username" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "secret_accessor_members" {
  type    = map(string)
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}
