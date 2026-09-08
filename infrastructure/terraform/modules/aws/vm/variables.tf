variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any

  validation {
    condition = alltrue([
      for image in values(var.config.image_map) :
      can(regex("^/.+$", image.aws))
      if contains(keys(image), "aws")
    ])
    error_message = "AWS image_map values must be SSM parameter paths starting with /; direct AMI IDs are not supported."
  }
}

variable "network" {
  description = "Outputs of the aws_network module. Subnet/security-group IDs are null when the configuration has no AWS VMs."
  type = object({
    management_subnet_id = string
    workload_subnet_id   = string
    security_group_ids   = map(string)
  })
}
