# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "RG-app-g1" {
  name     = "RG-app-g1"
  location = "West Europe"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "app-virtual-network-g1" {
  name                = "app-virtual-network-g1"
  resource_group_name = azurerm_resource_group.RG-app-g1.name
  location            = azurerm_resource_group.RG-app-g1.location
  address_space       = ["10.0.1.0/16"]
}

# Create subnet
resource "azurerm_subnet" "app-g1-subnet" {
    name                 = "app-g1-subnet"
    resource_group_name  = azurerm_resource_group.RG-app-g1.name
    virtual_network_name = azurerm_virtual_network.app-virtual-network-g1.name
    address_prefixes       = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "app-g1-publicip" {
    name                         = "app-g1-publicip"
    location                     = "West Europe"
    resource_group_name          = azurerm_resource_group.RG-app-g1.name
    allocation_method            = "Dynamic"

    tags = {
        environment = "Migration lift and shift"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "app-g1-nsg" {
    name                = "app-g1-networkSecurityGroup"
    location            = "West Europe"
    resource_group_name = azurerm_resource_group.RG-app-g1.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "Migration lift and shift"
    }
}

# Create network interface
resource "azurerm_network_interface" "app-g1-nic" {
    name                      = "app-g1-NIC"
    location                  = "West Europe"
    resource_group_name       = azurerm_resource_group.RG-app-g1.name

    ip_configuration {
        name                          = "app-g1-NicConfiguration"
        subnet_id                     = azurerm_subnet.app-g1-subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.app-g1-publicip.id
    }

    tags = {
        environment = "Migration lift and shift"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "NIC-NSG" {
    network_interface_id      = azurerm_network_interface.app-g1-nic.id
    network_security_group_id = azurerm_network_security_group.app-g1-nsg.id
}


# Create (and display) an SSH key
resource "tls_private_key" "app_ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { value = tls_private_key.app_ssh.private_key_pem }

# Create virtual machines
resource "azurerm_linux_virtual_machine" "app-deploy-vms" {
    count                 = 3
    name                  = "${ count.index == 0 ? "WEB-SERVER" : (count.index == 1 ? "APP-SERVER" : "BDD-SERVER")}"
    location              = "West Europe"
    resource_group_name   = azurerm_resource_group.RG-app-g1.name
    network_interface_ids = [azurerm_network_interface.app-g1-nic.id]
    size                  = "Standard_DS1_v2"

    

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "14.04-LTS"
        version   = "latest"
    }

    os_disk {
        name              = "app-osdisk"
        caching           = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    
    computer_name  = "${ count.index == 0 ? "WEB-SERVER" : (count.index == 1 ? "APP-SERVER" : "BDD-SERVER")}"
    admin_username = "azureuser"
    admin_password = "Plb1234!"
    disable_password_authentication = false
    

    admin_ssh_key {
        username       = "azureuser"
        public_key     = tls_private_key.app_ssh.public_key_openssh
    }

    tags = {
        environment = "Migration lift and shift"
    }
}







