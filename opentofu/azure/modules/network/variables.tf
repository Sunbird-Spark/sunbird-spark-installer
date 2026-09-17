variable "environment" {
    type        = string
    description = "environment name. All resources will be prefixed with this value."
}

variable "building_block" {
    type        = string
    description = "Building block name. All resources will be prefixed with this value."
}

variable "location" {
    type        = string
    description = "Azure location to create the resources."
    default     = "Central India"
}

variable "additional_tags" {
    type        = map(string)
    description = "Additional tags for the resources. These tags will be applied to all the resources."
    default     = {}
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Existing Azure resource group name."
  type        = string
}

variable "skip_network_module" {
  type        = bool
  description = "When true, reuse existing VNet/subnets via data sources (vnet_name, aks_subnet_name, runner_subnet_name required). When false, OpenTofu creates VNet and subnets."
  default     = false
}

variable "vnet_name" {
  type        = string
  description = "Name of existing VNet to reuse. Required when skip_network_module is true."
  default     = ""
}

variable "aks_subnet_name" {
  type        = string
  description = "Name of existing AKS subnet to reuse. Required when skip_network_module is true."
  default     = ""
}

variable "runner_subnet_name" {
  type        = string
  description = "Name of existing runner subnet to reuse. Required when skip_network_module is true."
  default     = ""
}

variable "vpn_enabled" {
  type        = bool
  description = "When true, Pritunl VPN is installed on the runner VM (VM has public IP). When false, Azure Bastion is created by OpenTofu for developer access (no public IP on VM)."
  default     = true
}

variable "vnet_address_space" {
  type        = list(string)
  description = "VNet address space."
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_cidr" {
  type        = list(string)
  description = "AKS subnet address prefixes."
  default     = ["10.0.0.0/20"]
}

variable "runner_subnet_cidr" {
  type        = list(string)
  description = "Runner VM subnet address prefixes."
  default     = ["10.0.16.0/28"]
}

variable "bastion_subnet_cidr" {
  type        = list(string)
  description = "AzureBastionSubnet address prefixes. Must be /26 or larger."
  default     = ["10.0.17.0/26"]
}