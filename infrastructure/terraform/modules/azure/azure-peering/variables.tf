variable "config" {
  description = "Decoded project configuration used for peering names."
  type        = any
}

variable "primary_region_key" {
  description = "Logical key of the primary Azure region."
  type        = string
}

variable "peer_regions" {
  description = "Non-primary Azure regions that require bidirectional VNet peering."
  type        = any
}

variable "resource_group_names" {
  description = "Azure resource-group names keyed by logical region."
  type        = map(string)
}

variable "virtual_network_names" {
  description = "Azure VNet names keyed by logical region."
  type        = map(string)
}

variable "virtual_network_ids" {
  description = "Azure VNet resource IDs keyed by logical region."
  type        = map(string)
}
