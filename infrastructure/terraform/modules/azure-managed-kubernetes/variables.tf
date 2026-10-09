variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network" {
  description = "Azure network identifiers for the managed cluster location."
  type = object({
    region            = string
    zone              = optional(string)
    vnet_id           = string
    vnet_name         = string
    public_subnet_id  = string
    private_subnet_id = string
    nat_public_ip     = string
  })
}

variable "resource_group_name" {
  description = "Resource group that owns the AKS cluster."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace used by AKS Container Insights."
  type        = string
}
