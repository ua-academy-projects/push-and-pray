output "iam_role_arns" {
    description = "ARNs of each workload VM's dedicated IAM role, by VM key."
    value       = { for name, role in aws_iam_role.workload : name => role.arn }
}

output "iam_role_names" {
    description = "Names of each workload VM's dedicated IAM role, by VM key."
    value       = { for name, role in aws_iam_role.workload : name => role.name }
}

output "instance_profile_names" {
    description = "Names of each workload VM's dedicated instance profile, by VM key."
    value       = { for name, profile in aws_iam_instance_profile.workload : name => profile.name }
}
