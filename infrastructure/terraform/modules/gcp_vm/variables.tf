variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "subnets" {
  description = "Subnet IDs created by gcp_network."
  type = object({
    management_subnet_id = string
    vm_subnet_id         = string
  })
}

variable "service_account_emails" {
  description = "Runtime service account emails keyed by VM name."
  type        = map(string)
}
