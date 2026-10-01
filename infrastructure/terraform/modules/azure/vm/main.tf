resource "azurerm_public_ip" "vm" {
  for_each = {
    for name, vm in var.vms : name => vm
    if vm.assign_public_ip
  }

  name                = "${local.vm_names[each.key]}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = try([each.value.location.vm_zone], null)
  tags                = local.tags_by_vm[each.key]
}

resource "azurerm_network_interface" "vm" {
  for_each = var.vms

  name                  = "${local.vm_names[each.key]}-nic"
  resource_group_name   = var.resource_group_name
  location              = var.location
  tags                  = local.tags_by_vm[each.key]
  ip_forwarding_enabled = each.value.role == "bastion"

  ip_configuration {
    name                          = "primary"
    subnet_id                     = local.subnet_ids_by_vm[each.key]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = each.value.assign_public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  for_each = var.vms

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.network_security_group_ids[each.value.role]
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = var.vms

  name                = local.vm_names[each.key]
  computer_name       = replace(local.vm_names[each.key], "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = each.value.instance_type
  zone                = try(each.value.location.vm_zone, null)

  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]

  admin_ssh_key {
    username   = local.admin_username
    public_key = local.admin_ssh_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "${local.vm_names[each.key]}-os"
    caching              = "ReadWrite"
    storage_account_type = each.value.disk_type
    disk_size_gb         = each.value.boot_disk.size_gb
  }

  source_image_reference {
    publisher = each.value.image_config.publisher
    offer     = each.value.image_config.offer
    sku       = each.value.image_config.sku
    version   = each.value.image_config.version
  }

  custom_data = each.value.role == "bastion" ? base64encode(templatefile(
    "${path.module}/templates/bastion-cloud-init.yaml.tftpl",
    { ssh_port = var.bastion_ssh_port },
  )) : null

  boot_diagnostics {}
  tags = local.tags_by_vm[each.key]

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["bastion", "ui"], each.value.role)
      error_message = "Only Azure VMs with role bastion or ui may receive a public IP."
    }
  }

  depends_on = [azurerm_network_interface_security_group_association.vm]
}
