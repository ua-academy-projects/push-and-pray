variable "config" {
  description = "Decoded project configuration containing VMs, clouds, networks, and Tailscale settings."
  type        = any
}

variable "azure_trusted_vnet_cidrs" {
  description = "Private Azure VNet CIDRs that may be advertised through Tailscale."
  type        = list(string)
}
