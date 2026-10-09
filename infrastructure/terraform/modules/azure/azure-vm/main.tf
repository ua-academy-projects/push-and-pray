resource "azurerm_public_ip" "vm" {
  for_each = {
    for name, vm in local.resolved_vms : name => vm if vm.assign_public_ip
  }

  name                = "${local.resource_prefix}-${each.key}-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zone == null ? null : [local.zone]
  tags                = merge(local.common_tags, lookup(each.value, "labels", {}), { role = each.value.role })

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_network_interface" "vm" {
  for_each = local.resolved_vms

  name                = "${local.resource_prefix}-${each.key}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, lookup(each.value, "labels", {}), { role = each.value.role })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_ids[contains(["bastion", "ui"], each.value.role) ? "management" : "workload"]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = each.value.assign_public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  for_each = local.resolved_vms

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.network_security_group_ids[each.key]
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.resolved_vms

  name                = "${local.resource_prefix}-${each.key}"
  computer_name       = substr(replace("${local.resource_prefix}-${each.key}", "-", ""), 0, 63)
  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = local.zone
  size                = each.value.machine_type
  admin_username      = local.primary_ssh_user
  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]
  disable_password_authentication = true
  custom_data                     = try(base64encode(var.tailscale_cloud_init[each.key]), null)

  admin_ssh_key {
    username   = local.primary_ssh_user
    public_key = var.config.ssh_users[local.primary_ssh_user]
  }

  os_disk {
    name                 = "${local.resource_prefix}-${each.key}-os"
    caching              = "ReadWrite"
    storage_account_type = each.value.boot_disk.type
    disk_size_gb         = each.value.boot_disk.size_gb
  }

  source_image_reference {
    publisher = split(":", each.value.image)[0]
    offer     = split(":", each.value.image)[1]
    sku       = split(":", each.value.image)[2]
    version   = split(":", each.value.image)[3]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_ids[each.key]]
  }

  tags = merge(
    local.common_tags,
    lookup(each.value, "labels", {}),
    {
      role              = each.value.role
      database_mode     = var.database_runtime.mode
      database_cloud    = var.database_runtime.cloud
      database_host     = var.database_runtime.host
      database_port     = tostring(var.database_runtime.port)
      database_name     = var.database_runtime.name
      database_user     = var.database_runtime.username
      database_sslmode  = var.database_runtime.sslmode
      database_secret   = var.database_runtime.secret_reference
      queue_backend     = var.database_runtime.queue_backend
      queue_host        = var.database_runtime.queue_host
      queue_port        = tostring(var.database_runtime.queue_port)
      queue_username    = var.database_runtime.queue_username
      queue_vhost       = var.database_runtime.queue_vhost
      queue_secret      = var.database_runtime.queue_secret_reference
      identity_client   = var.identity_client_ids[each.key]
      identity_resource = var.identity_ids[each.key]
      secret_vault_uri  = var.application_key_vault_uri
    },
    each.value.role == "k3s" ? {
      k3s_role      = each.value.k3s_role
      k3s_bootstrap = tostring(each.value.k3s_bootstrap)
    } : {},
  )

  lifecycle {
    # The short-lived bootstrap key is only needed when a VM is created.
    # Its later rotation must not replace an existing instance.
    ignore_changes = [custom_data]

    precondition {
      condition     = length(split(":", each.value.image)) == 4
      error_message = "Azure VM images must use publisher:offer:sku:version format."
    }

    precondition {
      condition = (
        !each.value.assign_public_ip ||
        each.value.role == "bastion" ||
        try(each.value.public_endpoint.hostname, null) != null
      )
      error_message = "Only the bastion or a workload with public_endpoint may receive a public IP."
    }
  }

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

resource "azurerm_managed_disk" "additional" {
  for_each = local.disks

  name                 = "${local.resource_prefix}-${each.key}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = each.value.type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb
  zone                 = local.zone
  tags                 = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "additional" {
  for_each = local.disks

  managed_disk_id    = azurerm_managed_disk.additional[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.value.vm_name].id
  lun                = each.value.lun
  caching            = "ReadWrite"
}
