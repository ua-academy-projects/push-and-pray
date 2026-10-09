variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "vms" {
  description = "Azure VMs keyed by logical workload name."
  type        = any
}

variable "region_key" {
  description = "Logical Azure region key used by this module instance."
  type        = string
}

variable "name_suffix" {
  description = "Optional suffix that keeps regional resource names unique."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  type     = string
  nullable = true
}

variable "location" {
  type     = string
  nullable = true
}

variable "subnet_ids" {
  type    = map(string)
  default = {}
}

variable "network_security_group_ids" {
  type    = map(string)
  default = {}
}

variable "identity_ids" {
  type    = map(string)
  default = {}
}

variable "identity_client_ids" {
  type    = map(string)
  default = {}
}

variable "application_key_vault_uri" {
  description = "Azure Key Vault URI containing application secrets."
  type        = string
  default     = null
  nullable    = true
}

variable "database_runtime" {
  description = "Non-secret database and queue connection metadata exposed to Ansible through Azure VM tags."
  type = object({
    mode                   = string
    cloud                  = string
    host                   = string
    port                   = number
    name                   = string
    username               = string
    sslmode                = string
    secret_reference       = string
    queue_backend          = string
    queue_host             = string
    queue_port             = number
    queue_username         = string
    queue_vhost            = string
    queue_secret_reference = string
  })
}


variable "tailscale_cloud_init" {
  description = "Rendered Tailscale cloud-init payloads keyed by logical VM name."
  type        = map(string)
  default     = {}
  sensitive   = true
}
