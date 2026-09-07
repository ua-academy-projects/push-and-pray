resource "aws_iam_role" "workload" {
    for_each = local.selected_vms
    name = "${local.resource_prefix}-${each.key}"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = { Service = "ec2.amazonaws.com"}
        }]
    })
}

resource "aws_iam_instance_profile" "workload" {
    for_each = local.selected_vms
    name = "${local.resource_prefix}-${each.key}"
    role = aws_iam_role.workload[each.key].name
}
