#################################################################
# Terraform template that will deploy:
#    * Windows Server VM on Microsoft Azure
#
# Version: 2.4
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2020.
#
#################################################################

terraform {
  required_version = ">= 0.12"
}

#########################################################
# Define the Azure provider
#########################################################
provider "azurerm" {
  #azurerm_subnet uses address_prefixes from 2.9.0
  #so pin this template to >= 2.9.0
  version = ">= 2.9.0"
  features {}
}

#########################################################
# Helper module for tagging
#########################################################
module "camtags" {
  source = "../Modules/camtags"
}

#########################################################
# Define the variables
#########################################################
variable "azure_region" {
  description = "Azure region to deploy infrastructure resources"
  default     = "West US"
}

variable "name_prefix" {
  description = "Prefix of names for Azure resources"
  default     = "singleVM"
}

variable "admin_user" {
  description = "Name of an administrative user to be created in virtual machine in this deployment"
  default     = "ibmadmin"
}

variable "admin_user_password" {
  description = "Password of the newly created administrative user"
}

#########################################################
# Deploy the network resources
#########################################################
resource "random_id" "default" {
  byte_length = "4"
}

resource "azurerm_resource_group" "default" {
  name     = "${var.name_prefix}-${random_id.default.hex}-rg"
  location = var.azure_region
  tags     = module.camtags.tagsmap
}

resource "azurerm_virtual_network" "default" {
  name                = "${var.name_prefix}-${random_id.default.hex}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name

  tags = {
    environment = "Terraform Basic VM"
  }
}

resource "azurerm_subnet" "vm" {
  name                 = "${var.name_prefix}-subnet-${random_id.default.hex}-vm"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "vm" {
  name                = "${var.name_prefix}-${random_id.default.hex}-vm-pip"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name
  allocation_method   = "Static"
  tags                = module.camtags.tagsmap
}

resource "azurerm_network_security_group" "vm" {
  depends_on		  = ["azurerm_network_interface.vm"]
  name                = "${var.name_prefix}-${random_id.default.hex}-vm-nsg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name
  tags                = module.camtags.tagsmap

  security_rule {
    name                       = "ssh-allow"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "custom-tcp-allow"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vm" {
  name                = "${var.name_prefix}-${random_id.default.hex}-vm-nic1"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name

  ip_configuration {
    name                          = "${var.name_prefix}-${random_id.default.hex}-vm-nic1-ipc"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
  tags                = module.camtags.tagsmap
}

resource "azurerm_network_interface_security_group_association" "vm" {
  depends_on		  = [azurerm_network_interface.vm, azurerm_network_security_group.vm]
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

#########################################################
# Deploy the storage resources
#########################################################
resource "azurerm_storage_account" "default" {
  name                     = format("st%s", random_id.default.hex)
  resource_group_name      = azurerm_resource_group.default.name
  location                 = var.azure_region
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = module.camtags.tagsmap

}

resource "azurerm_storage_container" "default" {
  name                  = "default-container"
  storage_account_name  = azurerm_storage_account.default.name
  container_access_type = "private"
}

#########################################################
# Deploy the virtual machine resource
#########################################################
resource "azurerm_virtual_machine" "vm" {
  depends_on			= [azurerm_network_interface_security_group_association.vm]
  name                  = "${var.name_prefix}-vm"
  location              = var.azure_region
  resource_group_name   = azurerm_resource_group.default.name
  network_interface_ids = [azurerm_network_interface.vm.id]
  vm_size               = "Standard_F2"
  //admin_username      = "${var.admin_user}"
  //admin_password      = "${var.admin_user_password}"

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
 
  os_profile {
      admin_username = "${var.admin_user}"
      admin_password = "${var.admin_user_password}"
      computer_name  = "MyComputer-vm"
  }

  os_profile_windows_config {
      provision_vm_agent = true
  }

  storage_os_disk {
    name          = "${var.name_prefix}-vm-os-disk1"
    caching              = "ReadWrite"
    //storage_account_type = "Standard_LRS"
    create_option = "FromImage"
  }


  tags             = module.camtags.tagsmap
}

# resource "azurerm_virtual_machine_extension" "domjoin" {
#        name = "domjoin"   
#        location = "${var.location}"   
#        resource_group_name = azurerm_resource_group.default.name
#        virtual_machine_name = "${var.name_prefix}-vm"
#        publisher = "Microsoft.Compute"   
#        type = "JsonADDomainExtension"   
#        type_handler_version = "1.3"   
#        # What the settings mean: https://docs.microsoft.com/en-us/windows/desktop/api/lmjoin/nf-lmjoin-netjoindomain   
#        settings = <<SETTINGS   {   
#            "Name": "pixelrobots.co.uk",   
#            "OUPath": "OU=Servers,DC=pixelrobots,DC=co,DC=uk",   
#            "User": "pixelrobots.co.uk\\pr_admin",   
#            "Restart": "true",   "Options": "3"   
#         }   
#         SETTINGS   
        
#         protected_settings = <<PROTECTED_SETTINGS   
#         {   
#             "Password": "${var.admin_user_password}"   
#         }
#         PROTECTED_SETTINGS   
        
#         depends_on = ["azurerm_virtual_machine.vm"]   
# }

#########################################################
# Output
#########################################################
output "azure_vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "azure_vm_private_ip" {
  value = azurerm_network_interface.vm.private_ip_address
}
