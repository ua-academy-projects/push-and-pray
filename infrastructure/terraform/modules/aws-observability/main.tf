data "aws_partition" "current" {}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = var.role_names

  role       = each.value
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}
