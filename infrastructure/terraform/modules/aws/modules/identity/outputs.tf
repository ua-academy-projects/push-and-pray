output "identity" {
  description = "ARN of the IAM role. The AWS equivalent of the GCP module's service-account email."
  value       = aws_iam_role.workload.arn
}

output "member" {
  description = "The role as a policy principal. On AWS this is the ARN itself."
  value       = aws_iam_role.workload.arn
}

output "role_name" {
  description = "Name of the role, for attaching inline policies to it."
  value       = aws_iam_role.workload.name
}

output "role_arn" {
  description = "ARN of the role."
  value       = aws_iam_role.workload.arn
}

output "role_unique_id" {
  description = "Stable unique ID of the role, which survives a rename."
  value       = aws_iam_role.workload.unique_id
}

output "instance_profile_name" {
  description = "Name of the instance profile, which is what an EC2 instance actually takes."
  value       = aws_iam_instance_profile.workload.name
}

output "instance_profile_arn" {
  description = "ARN of the instance profile."
  value       = aws_iam_instance_profile.workload.arn
}

output "instance_profile_unique_id" {
  description = "Stable unique ID of the instance profile."
  value       = aws_iam_instance_profile.workload.unique_id
}
