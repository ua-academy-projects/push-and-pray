output "gcp_vms" {
  value = try(module.gcp_vm[0].vms, {})
}

output "aws_vms" {
  value = try(module.aws_vm[0].vms, {})
}
