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
  description = "Name of existing VNet to reuse. Required when network_module_enabled is false."
  default     = ""
}

variable "aks_subnet_name" {
  type        = string
  description = "Name of existing AKS subnet to reuse. Required when network_module_enabled is false."
  default     = ""
}

variable "runner_subnet_name" {
  type        = string
  description = "Name of existing runner subnet to reuse. Required when network_module_enabled is false."
  default     = ""
}