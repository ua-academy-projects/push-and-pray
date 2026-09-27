variable "enabled" {
  description = "Create the RDS resources."
  type        = bool
}

variable "clients_share_cloud" {
  description = "Whether all database clients share the RDS cloud and private network."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for RDS resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC containing RDS and its clients."
  type        = string
  nullable    = true
}

variable "subnet_ids" {
  description = "Private subnet IDs spanning at least two Availability Zones."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "EC2 security groups allowed to connect to PostgreSQL."
  type        = map(string)
}

variable "database_name" {
  type = string
}

variable "username" {
  type = string
}

variable "port" {
  type    = number
  default = 5432
}

variable "engine_version" {
  type = string
}

variable "parameter_group_family" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "skip_final_snapshot" {
  type = bool
}

variable "final_snapshot_identifier" {
  type     = string
  nullable = true
}

variable "deletion_protection" {
  type = bool
}

variable "tags" {
  type    = map(string)
  default = {}
}
