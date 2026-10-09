variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network" {
  description = "AWS network identifiers for the managed cluster location."
  type = object({
    region                 = string
    vpc_id                 = string
    public_subnet_id       = string
    private_subnet_id      = string
    private_route_table_id = string
    database_subnet_ids    = list(string)
  })
}

variable "bastion_security_group_id" {
  description = "Security group attached to the Technitium and Tailscale bastion."
  type        = string
}
