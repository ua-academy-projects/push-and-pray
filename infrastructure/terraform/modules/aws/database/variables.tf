variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "vpc_id" {
  description = "VPC that contains the managed database."
  type        = string
  nullable    = true
}

variable "subnet_ids" {
  description = "Private subnets for the RDS DB subnet group."
  type        = list(string)
}

variable "client_security_group_ids" {
  description = "Workload security groups allowed to connect to PostgreSQL."
  type        = map(string)
}
