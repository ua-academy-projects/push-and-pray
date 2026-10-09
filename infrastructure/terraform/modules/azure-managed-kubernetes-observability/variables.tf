variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "cluster" {
  description = "AKS cluster identity used to scope Azure Monitor queries."
  type = object({
    id                  = string
    name                = string
    location            = string
    resource_group_name = string
    endpoint            = string
  })
}

variable "workspace_id" {
  description = "Log Analytics workspace receiving Container Insights data."
  type        = string
}

variable "application_insights_id" {
  description = "Application Insights component used by the HTTPS availability test."
  type        = string
}

variable "action_group_id" {
  description = "Optional Azure Monitor Action Group for alert notifications."
  type        = string
  nullable    = true
}
