locals {
  instance_tags = merge(
    var.tags,
    {
      Name = var.name
      role = var.role
    },
  )
}
