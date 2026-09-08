output "instance_profile_names" {
  description = "IAM instance profile names keyed by logical AWS VM name."
  value = {
    for name, profile in aws_iam_instance_profile.vm : name => profile.name
  }
}
