variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR range of the management subnet."
  type        = string
}

variable "workload_subnet_cidr" {
  description = "CIDR range of the workload subnet."
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

variable "history_api_port" {
  description = "Port used by UI to connect to the History API."
  type        = number
}

variable "postgresql_port" {
  description = "Port used by workloads to connect to PostgreSQL on the infra VM."
  type        = number
}

variable "ui_public_ports" {
  description = "Public TCP ports exposed on the UI VM"
  type        = list(string)
  default     = ["80", "443"]
}
