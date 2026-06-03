terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
    tls = {
      version = "~> 4.0"
      source  = "hashicorp/tls"
    }
  }
}

# Auto-generate SSH key pair — no need to provide one manually
resource "tls_private_key" "runner_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

locals {
  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
  environment_name = "${var.building_block}-${var.environment}"
}

# Public IP for VPN clients to connect
resource "azurerm_public_ip" "runner_pip" {
  name                = "${local.environment_name}-runner-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.common_tags, var.additional_tags)
}

# NSG — allow VPN (UDP 1194), Pritunl UI (TCP 443), SSH from VPN range only
resource "azurerm_network_security_group" "runner_nsg" {
  name                = "${local.environment_name}-runner-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, var.additional_tags)

  security_rule {
    name                       = "allow-wireguard-vpn"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "1194"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-pritunl-ui"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-from-vpn"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.pritunl_vpn_network
    destination_address_prefix = "*"
  }
}

# NIC
resource "azurerm_network_interface" "runner_nic" {
  name                = "${local.environment_name}-runner-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, var.additional_tags)

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.runner_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.runner_pip.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "runner_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.runner_nic.id
  network_security_group_id = azurerm_network_security_group.runner_nsg.id
}

# User-assigned managed identity for VM
resource "azurerm_user_assigned_identity" "runner_identity" {
  name                = "${local.environment_name}-runner-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, var.additional_tags)
}

# Contributor role on resource group — for OpenTofu to manage resources
resource "azurerm_role_assignment" "runner_contributor" {
  principal_id         = azurerm_user_assigned_identity.runner_identity.principal_id
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
}

# Storage Blob Data Contributor — for OpenTofu state
resource "azurerm_role_assignment" "runner_storage" {
  principal_id         = azurerm_user_assigned_identity.runner_identity.principal_id
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Storage Blob Data Contributor"
}

# cloud-init template
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    github_runner_token = var.github_runner_token
    github_org          = var.github_org
    github_repo         = var.github_repo
    pritunl_vpn_network = var.pritunl_vpn_network
    pritunl_org_name    = var.pritunl_org_name
    pritunl_users_json  = jsonencode(var.pritunl_users)
    environment_name    = local.environment_name
  }
}

# VM
resource "azurerm_linux_virtual_machine" "runner" {
  name                = "${local.environment_name}-runner"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  custom_data         = base64encode(data.template_file.cloud_init.rendered)
  tags                = merge(local.common_tags, var.additional_tags)

  network_interface_ids = [azurerm_network_interface.runner_nic.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.runner_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runner_identity.id]
  }

  depends_on = [
    azurerm_role_assignment.runner_contributor,
    azurerm_role_assignment.runner_storage
  ]
}
