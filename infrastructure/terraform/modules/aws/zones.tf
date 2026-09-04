data "aws_availability_zones" "available" {
  count = local.enabled ? 1 : 0
  state = "available"
}