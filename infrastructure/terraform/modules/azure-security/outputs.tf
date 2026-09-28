output "network_security_group_ids" {
  description = "Azure NSG IDs keyed by logical location and functional tag."
  value = {
    for location in keys(var.networks) : location => {
      for tag in values(local.functional_tags) : tag.tag => azurerm_network_security_group.tag[tag.key].id
      if tag.location == location
    }
  }
}
