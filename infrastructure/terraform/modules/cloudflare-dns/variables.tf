variable "zone_id" {
  description = "Cloudflare zone identifier containing the UI hostname."
  type        = string
  nullable    = false
}

variable "hostname" {
  description = "Public UI hostname."
  type        = string
  nullable    = false
}

variable "ipv4_address" {
  description = "Current public IPv4 address of the UI VM."
  type        = string
  nullable    = false
}
