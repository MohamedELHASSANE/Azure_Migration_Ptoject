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
# resource "azurerm_resource_group" "prod-RG-app-g1" {
#   name     = "prod-RG-app-g1"
#   location = "West Europe"
# }

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "prod-app-virtual-network-g1" {
  name                = "prod-app-virtual-network-g1"
  resource_group_name = "RG-LABS-01"
  location            = "West Europe"
  address_space       = ["10.2.0.0/16"]
}

# Create subnet
resource "azurerm_subnet" "prod-app-g1-subnet" {
  name                 = "prod-app-g1-subnet"
  resource_group_name  = "RG-LABS-01"
  virtual_network_name = azurerm_virtual_network.prod-app-virtual-network-g1.name
  address_prefixes     = ["10.2.0.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "prod-app-g1-publicip" {
  count               = 4
  name                = "prod-app-g1-publicip-${count.index + 1}"
  location            = "West Europe"
  resource_group_name = "RG-LABS-01"
  allocation_method   = "Dynamic"

  tags = {
    environment = "Production Infrastructure"
  }
}

resource "azurerm_lb" "prod-load-balancer" {
  name                = "prod-load-balancer"
  location            = "West Europe"
  resource_group_name = "RG-LABS-01"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.prod-app-g1-publicip[3].id
  }

  tags = {
    environment = "Production Infrastructure"
  }
}

resource "azurerm_lb_backend_address_pool" "prod-load-balancer-bap" {
  resource_group_name = "RG-LABS-01"
  loadbalancer_id     = azurerm_lb.prod-load-balancer.id
  name                = "BackEndAddressPool"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "prod-app-g1-nsg" {
  name                = "prod-app-g1-networkSecurityGroup"
  location            = "West Europe"
  resource_group_name = "RG-LABS-01"

  tags = {
    environment = "Production Infrastructure"
  }
}

resource "azurerm_network_security_rule" "SSH" {
  name                        = "SSH"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "RG-LABS-01"
  network_security_group_name = azurerm_network_security_group.prod-app-g1-nsg.name
}

resource "azurerm_network_security_rule" "HTTP" {
  name                        = "HTTP"
  priority                    = 1002
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "RG-LABS-01"
  network_security_group_name = azurerm_network_security_group.prod-app-g1-nsg.name
}

resource "azurerm_network_security_rule" "HTTPS" {
  name                        = "HTTPS"
  priority                    = 1003
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "RG-LABS-01"
  network_security_group_name = azurerm_network_security_group.prod-app-g1-nsg.name
}

# Create network interface
resource "azurerm_network_interface" "prod-app-g1-nic" {
  count               = 3
  name                = "prod-app-g1-NIC-${count.index + 1}"
  location            = "West Europe"
  resource_group_name = "RG-LABS-01"

  ip_configuration {
    name                          = "prod-app-g1-NicConfiguration"
    subnet_id                     = azurerm_subnet.prod-app-g1-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.prod-app-g1-publicip[count.index].id
  }

  tags = {
    environment = "Production Infrastructure"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "prod-NIC-NSG" {
  count                     = 3
  network_interface_id      = azurerm_network_interface.prod-app-g1-nic[count.index].id
  network_security_group_id = azurerm_network_security_group.prod-app-g1-nsg.id
}


# Create (and display) an SSH key
resource "tls_private_key" "prod-app_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
output "tls_private_key" { value = tls_private_key.prod-app_ssh.private_key_pem }

# Create virtual machines
resource "azurerm_linux_virtual_machine" "prod-app-deploy-vms" {
  count                 = 3
  name                  = count.index == 0 ? "MASTER" : (count.index == 1 ? "WORKER-1" : "WORKER-2")
  location              = "West Europe"
  resource_group_name   = "RG-LABS-01"
  network_interface_ids = [azurerm_network_interface.prod-app-g1-nic[count.index].id]
  size                  = count.index == 0 ? "Standard_D2s_v3" : "Standard_DS1_v2"



  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "prod-app-osdisk-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  computer_name                   = count.index == 0 ? "MASTER" : (count.index == 1 ? "WORKER-1" : "WORKER-2")
  admin_username                  = "azureuser-prod"
  admin_password                  = "Plb1234!"
  disable_password_authentication = false


  admin_ssh_key {
    username   = "azureuser-prod"
    public_key = tls_private_key.prod-app_ssh.public_key_openssh
  }

  tags = {
    environment = "Production Infrastructure"
  }
}







