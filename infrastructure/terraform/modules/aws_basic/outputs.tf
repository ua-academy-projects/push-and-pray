output "instance_profile_names" {
  description = "EC2 instance profile names keyed by VM name."
  value = {
    for name, profile in aws_iam_instance_profile.profiles :
    name => profile.name
  }

  depends_on = [aws_iam_role_policy.readers]
}
