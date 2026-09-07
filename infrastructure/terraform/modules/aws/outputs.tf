output "names" {
    value = module.vm.names
}

output "internal_ips" {
    value = module.vm.internal_ips
}

output "public_ips" {
    value = module.vm.public_ips
}

output "network_tags" {
    value = module.vm.network_tags
}

output "iam_role_arns" {
    value = module.iam.iam_role_arns
}

output "iam_role_names" {
    value = module.iam.iam_role_names
}
