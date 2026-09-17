output "aws_instance_profile_name" {
  value = try(aws_iam_instance_profile.ec2[0].name, null)
}
output "aws_role_arn" {
  value = try(aws_iam_role.ec2[0].arn, null)
}
output "gcp_service_account_emails" {
  value = { for name, account in google_service_account.vm : name => account.email }
}
