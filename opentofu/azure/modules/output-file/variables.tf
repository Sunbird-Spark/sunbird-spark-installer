variable "env" {
  type        = string
  description = "Env name. All resources will be prefixed with this value in helm charts."
}

variable "environment" {
  type        = string
  description = "Envrionment name. All resources will be prefixed with this value in tofu."
}

variable "building_block" {
  type        = string
  description = "Building block name. All resources will be prefixed with this value."
}

variable "storage_account_name" {
  type        = string
  description = "Storage account name."
}

variable "storage_container_public" {
  type        = string
  description = "Public storage container name with blob access."
}

variable "storage_container_private" {
  type        = string
  description = "Private storage container name."
}

variable "base_location" {
  type        = string
  description = "Location of terrafrom execution folder."
}

variable "random_string" {
  type        = string
  description = "This string will be used to encrypt / mask various values. Use a strong random string in order to secure the applications. The string should be between 12 and 24 characters in length. If you forget the string, the application will stop working and the string cannot be retrieved."
  validation {
    condition     = length(var.random_string) >= 12 || length(var.random_string) <= 24
    error_message = "The string must have a length ranging from 12 to 24 characters."
  }
}
variable "private_ingressgateway_ip" {
  type        = string
  description = "Private LB IP."
}
variable "cloud_storage_provider" {
  description = "The cloud storage provider to use."
  type        = string
  default     = ""
}


variable "velero_container_name" {
  description = "The name of the Velero storage container."
  type        = string
  default     = ""
}

variable "azure_client_id" {
  type        = string
  description = "Client ID of the user-assigned managed identity for Workload Identity (for Azure blob storage access). Required when cloud_storage_provider is 'azure'."
  default     = ""
}

variable "managed_identity_principal_id" {
  type        = string
  description = "Principal ID of the user-assigned managed identity — used by addon storage modules (e.g. DIAL) to assign blob access roles."
  default     = ""
}

variable "k8s_service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account for Workload Identity (created by workload-identity module)."
  default     = "azure-managed-identity-sa"
}

variable "sunbird_encryption_key" {
  type        = string
  description = "Migration-only: OLD cluster's sunbird_encryption_key, used by learn-service to decrypt migrated PII. Empty for fresh installs (learn-service falls back to random_string)."
  default     = ""
  sensitive   = true
}

