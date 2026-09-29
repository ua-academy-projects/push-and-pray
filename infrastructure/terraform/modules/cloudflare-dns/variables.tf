variable "zone_id" {
  description = "Cloudflare zone identifier containing the public application hostname."
  type        = string
  nullable    = false
}

variable "hostname" {
  description = "Public application hostname."
  type        = string
  nullable    = false
}

variable "ipv4_address" {
  description = "Current public IPv4 address of the application endpoint."
  type        = string
  nullable    = false
}
