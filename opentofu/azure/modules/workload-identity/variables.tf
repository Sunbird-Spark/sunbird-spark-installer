variable "environment" {
  type        = string
  description = "Environment name. All resources will be prefixed with this value."
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

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the managed identity."
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the AKS cluster (from aks module output)."
}

variable "storage_account_id" {
  type        = string
  description = "Resource ID of the storage account to grant Storage Blob Data Contributor on."
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace where the service account lives."
  default     = "sunbird"
}

variable "k8s_service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account."
  default     = "workload-identity"
}
