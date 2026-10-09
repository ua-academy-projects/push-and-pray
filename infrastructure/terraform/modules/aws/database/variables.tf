variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "network" {
  description = "Outputs from the AWS network module."
  type        = any
}

variable "kubernetes" {
  description = "The aws_eks module. Only the EKS-managed cluster security group is read, which is the group pods run with in managed Kubernetes mode and so the one PostgreSQL has to accept."
  type        = any
}

