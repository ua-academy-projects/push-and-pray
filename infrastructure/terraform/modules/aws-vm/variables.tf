variable "name" {
  description = "Name used for the EC2 instance and IAM identity."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instance is created."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the instance."
  type        = list(string)
}

variable "role" {
  description = "Provider-independent OilScope role."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type resolved from the logical size."
  type        = string
}

variable "image_ssm_parameter" {
  description = "Canonical public SSM parameter that resolves the logical OS image to an AMI ID."
  type        = string

  validation {
    condition     = can(regex("^/aws/service/canonical/ubuntu/.+/ami-id$", var.image_ssm_parameter))
    error_message = "image_ssm_parameter must be a Canonical public Ubuntu AMI parameter."
  }
}

variable "internal_ip" {
  description = "Static private IPv4 address assigned to the instance."
  type        = string
}

variable "key_name" {
  description = "EC2 key pair used only for initial Ansible SSH access."
  type        = string
}

variable "root_volume_size_gb" {
  description = "Root volume size in GiB resolved from the logical size."
  type        = number
}

variable "root_volume_type" {
  description = "EBS volume type resolved from the logical size."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to allocate and associate a static Elastic IP."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
}
