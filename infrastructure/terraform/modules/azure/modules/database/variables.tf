variable "resource_prefix" {
  description = "Prefix used for names of database resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group the server and its endpoint are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the server."
  type        = string
}

variable "zone" {
  description = "Zone the server runs in, the same one as the VMs."
  type        = string
}

variable "subnet_id" {
  description = "ID of the database subnet the private endpoint sits in."
  type        = string
}

variable "subnet_cidr" {
  description = "Range of that subnet. The security rule admits clients to it rather than to the endpoint, which cannot join an application security group."
  type        = string
}

variable "network_security_group_name" {
  description = "The network's security group, which the rule admitting the clients is added to."
  type        = string
}

variable "client_application_security_group_ids" {
  description = "Application security groups allowed to reach the database on its port, keyed by the scope name."
  type        = map(string)
}

variable "rule_priority" {
  description = "Priority of that rule: after the firewall module's allow rules, before its deny."
  type        = number
  default     = 180
}

variable "settings" {
  description = "The database block of the project configuration."
  type = object({
    engine_version        = string
    storage_gb            = number
    name                  = string
    username              = string
    backup_retention_days = number
    deletion_protection   = bool
  })

  validation {
    condition     = var.settings.storage_gb <= 32767
    error_message = "storage_gb is larger than the largest disk Azure offers a flexible server."
  }

  validation {
    condition     = !contains(["azure_superuser", "azure_pg_admin", "admin", "administrator", "root", "guest", "public"], var.settings.username) && !startswith(var.settings.username, "pg_")
    error_message = "database.username is a name Azure reserves and refuses as the administrator login."
  }
}

variable "sku_name" {
  description = "Tier and size of the server, already resolved from the size label through the cloud profile, for example B_Standard_B1ms."
  type        = string
  nullable    = false
}

variable "port" {
  description = "Port PostgreSQL listens on. A flexible server always listens on 5432."
  type        = number
  default     = 5432

  validation {
    condition     = var.port == 5432
    error_message = "An Azure flexible server listens on 5432 and nothing else; service_ports.postgresql must be 5432."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
