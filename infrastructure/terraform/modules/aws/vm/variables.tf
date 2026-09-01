variable "name" {
  description = "Name used for the EC2 instance and related AWS resources."
  type        = string
}

variable "role" {
  description = "Functional role of the workload, independent from its resource name."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type resolved from the logical VM size."
  type        = string
}

variable "subnet_id" {
  description = "ID of the AWS subnet in which the EC2 instance is created."
  type        = string
}

variable "security_group_ids" {
  description = "IDs of the security groups attached to the EC2 instance."
  type        = list(string)
}

variable "private_ip" {
  description = "Static private IPv4 address assigned to the EC2 instance."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether AWS should assign a public IPv4 address to the EC2 instance."
  type        = bool
  default     = false
}

variable "boot_disk_size_gb" {
  description = "Size of the EC2 root EBS volume in GiB."
  type        = number
}

variable "boot_disk_type" {
  description = "EBS volume type for the EC2 root disk, for example gp3."
  type        = string
}

variable "tags" {
  description = "AWS tags applied to resources that support tags."
  type        = map(string)
}
