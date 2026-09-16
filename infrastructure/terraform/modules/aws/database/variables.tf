variable "resource_prefix" {
  type = string
}

variable "database" {
  type = object({
    name = string
    user = string
    port = number
  })
}

variable "managed_settings" {
  type = object({
    engine_version = string
    instance_class = string
  })
}

variable "database_subnet_ids" {
  description = "Private subnet IDs keyed by Availability Zone for the RDS DB subnet group."
  type        = map(string)
}

variable "security_group_id" {
  description = "Security group that admits PostgreSQL only from application workload groups."
  type        = string
}

variable "password" {
  description = "Generated database password. Stored as sensitive Terraform state and published to Secrets Manager separately."
  type        = string
  sensitive   = true
}

variable "tags" {
  type = map(string)
}
