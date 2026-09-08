variable "network_id" {
  description = "ID of the VPC network protected by these firewall rules."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix used in firewall rule names and network tags."
  type        = string
}

variable "bastion_ssh_port" {
  description = "External SSH port opened for the bastion."
  type        = number
}

variable "bastion_allowed_cidrs" {
  description = "CIDR ranges allowed to connect to the bastion."
  type        = list(string)
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 during bootstrap."
  type        = bool
}

variable "ui_public_ports" {
  description = "Public TCP ports exposed by the UI VM."
  type        = list(string)
}

variable "history_api_port" {
  description = "TCP port used by UI to access the History API."
  type        = number
}

variable "postgresql_port" {
  description = "TCP port used by workloads to access PostgreSQL."
  type        = number
}
