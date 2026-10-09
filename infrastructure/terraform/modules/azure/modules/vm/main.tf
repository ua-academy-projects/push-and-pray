resource "azurerm_public_ip" "public" {
  count = var.vm.assign_public_ip ? 1 : 0

  name                = "${var.name}-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.profile.zone]

  tags = var.tags
}

# The network interface is a resource of its own on Azure, created before the
# VM; GCP and AWS build it as part of the instance.
resource "azurerm_network_interface" "main" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Azure drops packets a network interface receives for someone else. A
  # subnet router has to accept them.
  ip_forwarding_enabled = var.vm.ip_forwarding

  ip_configuration {
    name      = "primary"
    subnet_id = var.subnet_id
    # A dynamic address stays with the interface until it is deleted, so a
    # node keeps it across restarts without one being written down.
    private_ip_address_allocation = var.vm.internal_ip == null ? "Dynamic" : "Static"
    private_ip_address            = var.vm.internal_ip
    public_ip_address_id          = one(azurerm_public_ip.public[*].id)
  }

  tags = var.tags
}

# Membership in a scope is a property of the network interface - where AWS
# lists security groups on the instance and GCP writes network tags on it.
resource "azurerm_network_interface_application_security_group_association" "scope" {
  for_each = var.application_security_group_ids

  network_interface_id          = azurerm_network_interface.main.id
  application_security_group_id = each.value
}

resource "azurerm_linux_virtual_machine" "workload" {
  name                = var.name
  computer_name       = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = local.vm_size
  zone                = var.profile.zone

  network_interface_ids = [azurerm_network_interface.main.id]

  admin_username                  = local.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = trimspace(var.ssh_users[local.admin_username])
  }

  custom_data = base64encode(local.custom_data)

  os_disk {
    name                 = "${var.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = local.boot_disk_type
    disk_size_gb         = local.boot_disk_size_gb
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  # Trusted launch, the counterpart of GCP's shielded VM.
  secure_boot_enabled = true
  vtpm_enabled        = true

  # Managed storage for the serial console, which is the only way in when
  # SSH is broken.
  boot_diagnostics {}

  tags = var.tags

  lifecycle {
    # Both force a new VM on Azure. cloud-init applies the users once, at
    # first boot - as on AWS, where a changed user_data never re-runs it - so
    # replacing a VM over a key would destroy it for nothing. Taint the VM to
    # pick up a changed user list.
    ignore_changes = [custom_data, admin_ssh_key]
  }
}
