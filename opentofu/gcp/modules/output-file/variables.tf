variable "env" {
  type        = string
  description = "Env name. All resources will be prefixed with this value in helm charts."
}

variable "environment" {
  type        = string
  description = "Environment name. All resources will be prefixed with this value in tofu."
}

variable "building_block" {
  type        = string
  description = "Building block name."
}

variable "storage_container_public" {
  type        = string
  description = "Public bucket name."
}

variable "storage_container_private" {
  type        = string
  description = "Private bucket name."
}

variable "base_location" {
  type        = string
  description = "Tofu execution folder location."
}

variable "random_string" {
  type        = string
  description = "Random string for encryption / masking. 12-24 chars."
  validation {
    condition     = length(var.random_string) >= 12 || length(var.random_string) <= 24
    error_message = "The string must have a length ranging from 12 to 24 characters."
  }
}

variable "private_ingressgateway_ip" {
  type        = string
  description = "Private LB IP."
}

variable "dial_state_container_public" {
  type        = string
  description = "DIAL state public bucket name."
}

variable "service_account_email" {
  type        = string
  description = "GCP service account email used by Workload Identity."
}

variable "k8s_service_account_name" {
  type        = string
  description = "K8s service account name annotated for Workload Identity."
  default     = "sunbird-sa"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID."
  default     = ""
}

variable "storage_class" {
  type        = string
  description = "GKE storage class."
  default     = ""
}

variable "cloud_storage_provider" {
  type        = string
  description = "Cloud storage provider."
  default     = ""
}

variable "cloud_storage_region" {
  type        = string
  description = "Cloud storage region."
  default     = ""
}

variable "velero_storage_container_private" {
  type        = string
  description = "Private bucket for Velero backups."
  default     = ""
}
