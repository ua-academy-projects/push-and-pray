variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "create_database_subnets" {
  description = "Create private subnets in two Availability Zones for Amazon RDS."
  type        = bool
  default     = false
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for the private RDS subnets."
  type        = list(string)
  default     = []
}

variable "create_workload_nat_gateway" {
  description = "Provide outbound Internet access to private workload VMs through a NAT Gateway."
  type        = bool
  default     = false
}
