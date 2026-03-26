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
  description = "Resource ID of the storage account to grant blob access on."
}

variable "kubernetes_host" {
  type        = string
  description = "Kubernetes API server host."
}

variable "kubernetes_client_certificate" {
  type        = string
  description = "Kubernetes client certificate (base64 encoded)."
  sensitive   = true
}

variable "kubernetes_client_key" {
  type        = string
  description = "Kubernetes client key (base64 encoded)."
  sensitive   = true
}

variable "kubernetes_cluster_ca_certificate" {
  type        = string
  description = "Kubernetes cluster CA certificate (base64 encoded)."
  sensitive   = true
}

variable "k8s_namespaces" {
  type        = list(string)
  description = "List of Kubernetes namespaces to create."
  default     = ["sunbird", "velero"]
}

variable "k8s_service_accounts" {
  type = map(object({
    namespace = string
    name      = string
  }))
  description = "Map of Kubernetes service accounts to create per namespace."
  default = {
    sunbird = {
      namespace = "sunbird"
      name      = "azure-managed-identity-sa"
    }
    velero = {
      namespace = "velero"
      name      = "azure-managed-identity-sa"
    }
  }
}

variable "container_names" {
  type        = list(string)
  description = "List of blob container names to grant access to."
  default     = []
}
