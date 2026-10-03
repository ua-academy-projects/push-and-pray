variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the workspace and the rule are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the workspace and the rule."
  type        = string
}

variable "instances" {
  description = "Every VM that ships logs, keyed by name: its resource ID and the identity its agent authenticates as."
  type = map(object({
    id          = string
    identity_id = string
  }))
}

variable "retention_days" {
  description = "How long the workspace keeps an entry. Raised to 30, the shortest this tier allows."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
