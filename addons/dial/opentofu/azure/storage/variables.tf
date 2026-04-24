variable "environment" {
  type        = string
  description = "Environment name (e.g., sunbird-demo)"
}

variable "storage_account_name" {
  type        = string
  description = "Existing storage account name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name where storage account exists"
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "unique_uuid" {
  type        = string
  description = "Unique UUID for container naming"
}

variable "building_block" {
  type        = string
  description = "Building block name (e.g., ed)"
}

variable "global_cloud_values_file" {
  type        = string
  description = "Absolute path to global-cloud-values.yaml"
}
