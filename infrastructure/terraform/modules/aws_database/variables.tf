variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "vpc_id" {
  description = "VPC that contains the database clients."
  type        = string
}

variable "database_subnet_ids" {
  description = "Private subnet IDs used by the RDS DB subnet group."
  type        = list(string)
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect to PostgreSQL."
  type        = map(string)
}

variable "password_secret_arn" {
  description = "ARN of the existing Secrets Manager secret for the database password."
  type        = string
}
