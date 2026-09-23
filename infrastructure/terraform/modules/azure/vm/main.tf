resource "azurerm_public_ip" "workload" {
  for_each = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }

  name                = "${local.resource_prefix}-${each.key}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "workload" {
  for_each = local.selected_vms

  name                = "${local.resource_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = contains(each.value.roles, "bastion") ? var.management_subnet_id : var.workload_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = each.value.assign_public_ip ? azurerm_public_ip.workload[each.key].id : null
  }
}

resource "azurerm_linux_virtual_machine" "workload" {
  for_each = local.selected_vms

  name                  = "${local.resource_prefix}-${each.key}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.config.machine_types[each.value.machine_type]["azure"]
  admin_username        = keys(var.config.ssh_users)[0]
  network_interface_ids = [azurerm_network_interface.workload[each.key].id]

  admin_ssh_key {
    username   = keys(var.config.ssh_users)[0]
    public_key = values(var.config.ssh_users)[0]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.config.disk_types[each.value.boot_disk.type]["azure"]
    disk_size_gb         = max(each.value.boot_disk.size_gb, 30)
  }

  source_image_reference {
    publisher = local.image_ref[each.key][0]
    offer     = local.image_ref[each.key][1]
    sku       = local.image_ref[each.key][2]
    version   = local.image_ref[each.key][3]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_ids[each.key]]
  }

  tags = merge(
    local.merged_common_tags,
    try(each.value.labels, {}),
    {
      Name  = "${local.resource_prefix}-${each.key}"
      Roles = join(",", each.value.roles)
      Cloud = "azure"
    }
  )
}