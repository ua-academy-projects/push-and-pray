variable "instances" {
  description = "Azure virtual machines keyed by logical workload name."
  type        = any
}

variable "name_prefix" {
  description = "Prefix used for Azure monitoring resources."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group used for shared monitoring resources."
  type        = string
  nullable    = true
}

variable "location" {
  description = "Primary Azure location for shared monitoring resources."
  type        = string
  nullable    = true
}

variable "notification_email" {
  description = "Email address used by the Azure Monitor action group."
  type        = string
}

variable "public_endpoint_hostname" {
  description = "Public HTTPS hostname checked by Application Insights."
  type        = string
  default     = null
  nullable    = true
}

variable "cpu_threshold" {
  description = "Average VM CPU percentage that triggers an alert."
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_threshold > 0 && var.cpu_threshold <= 100
    error_message = "cpu_threshold must be greater than 0 and no more than 100."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention period."
  type        = number
  default     = 30
}

variable "synthetic_monitoring_enabled" {
  description = "Create the public HTTPS availability test and alert."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to Azure monitoring resources."
  type        = map(string)
  default     = {}
}
