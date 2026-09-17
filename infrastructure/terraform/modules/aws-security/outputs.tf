output "security_group_ids" {
  description = "AWS security group IDs keyed by logical location and VM tag."
  value = {
    for location in keys(var.networks) : location => {
      for tag in values(local.tags) : tag.tag => aws_security_group.tag[tag.key].id
      if tag.location == location
    }
  }
}
