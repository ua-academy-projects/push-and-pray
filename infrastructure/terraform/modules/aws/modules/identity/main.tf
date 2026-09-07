resource "aws_iam_role" "workload" {
  name        = var.name
  description = coalesce(var.description, "Runtime identity for the ${var.name} workload instance")

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

# AWS cannot attach a role to an instance directly; the profile is the carrier.
resource "aws_iam_instance_profile" "workload" {
  name = var.name
  role = aws_iam_role.workload.name

  tags = var.tags
}
