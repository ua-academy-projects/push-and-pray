variable "resource_prefix" {
  description = "Prefix used for AWS network resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR range of the AWS VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR range."
  }
}

variable "availability_zone" {
  description = "Availability zone resolved from the logical location."
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR range of the public management subnet."
  type        = string
}

variable "workload_subnet_cidr" {
  description = "CIDR range of the private workload subnet."
  type        = string
}

variable "bastion_ssh_port" {
  description = "External SSH port opened for the bastion."
  type        = number
}

variable "bastion_allowed_cidrs" {
  description = "Source CIDRs allowed to connect to the bastion."
  type        = list(string)
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Whether to temporarily allow bastion SSH on port 22."
  type        = bool
  default     = false
}

variable "history_api_port" {
  description = "Port used by UI to connect to the History API."
  type        = number
}

variable "postgresql_port" {
  description = "Port used by workloads to connect to PostgreSQL."
  type        = number
}

variable "ui_public_ports" {
  description = "Public TCP ports exposed by the UI."
  type        = list(number)
}

variable "tags" {
  description = "Common tags applied to AWS network resources."
  type        = map(string)
}
