output "public_ips" {
  description = "Public IP addresses keyed by VM name."
  value       = merge(module.gcp_vm.public_ips, module.aws_vm.public_ips)
}
