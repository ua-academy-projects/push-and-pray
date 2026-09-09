variable "config" {
  type = any
}

variable "management_subnet_id" {
  type = string
}

variable "workload_subnet_id" {
  type = string
}

variable "service_account_emails" {
  description = "Service account email per VM key, from the iam module."
  type        = map(string)
}

variable "public_ips" {
  description = "Static public IP address per VM key with assign_public_ip = true, from the addresses module."
  type        = map(string)
}
