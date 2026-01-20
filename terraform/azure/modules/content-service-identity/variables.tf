variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name where managed identity will be created"
}

variable "location" {
  type        = string
  description = "Azure region for the managed identity"
}

variable "building_block" {
  type        = string
  description = "Building block name (e.g., knowledgebb)"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"
}

variable "storage_account_id" {
  type        = string
  description = "Storage account resource ID for role assignment"
}

variable "oidc_issuer_url" {
  type        = string
  description = "AKS OIDC issuer URL for workload identity federation"
}

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace where the service account will be created"
  default     = "sunbird"
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account"
  default     = "content-service-sa"
}

