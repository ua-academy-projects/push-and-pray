variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "vms" {
  description = "Azure VMs selected by the root module, including an automatically added bastion when required."
  type        = any
}

variable "region_key" {
  description = "Logical Azure region key used by this module instance."
  type        = string
}

variable "location" {
  description = "Concrete Azure location used by this module instance."
  type        = string
}

variable "name_suffix" {
  description = "Optional suffix that keeps regional resource names unique."
  type        = string
  default     = ""
}

variable "network" {
  description = "Regional Azure network configuration."
  type        = any
}

variable "create_database_subnet" {
  description = "Create a delegated subnet for Azure Database for PostgreSQL Flexible Server."
  type        = bool
  default     = false
}

variable "database_subnet_cidr" {
  description = "CIDR block for the delegated PostgreSQL subnet."
  type        = string
  default     = "10.2.2.0/24"
}

variable "create_workload_nat_gateway" {
  description = "Provide outbound Internet access to private Azure workload VMs through a NAT Gateway."
  type        = bool
  default     = false
}
