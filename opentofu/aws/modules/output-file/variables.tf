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
  description = "Building block name. All resources will be prefixed with this value."
}

variable "aws_region" {
  type        = string
  description = "AWS region where resources are deployed."
}

variable "s3_bucket_public" {
  type        = string
  description = "Public S3 bucket name."
}

variable "s3_bucket_private" {
  type        = string
  description = "Private S3 bucket name."
}

variable "s3_bucket_velero" {
  type        = string
  description = "Velero S3 bucket name."
}

variable "base_location" {
  type        = string
  description = "Location of terraform execution folder."
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
  description = "Private LB IP (used for internal ingress annotations)."
}

variable "cloud_storage_provider" {
  description = "The cloud storage provider to use."
  type        = string
  default     = "aws"
}

variable "aws_iam_role_arn" {
  type        = string
  description = "ARN of the IAM role for IRSA workload identity (for S3 access). Required when cloud_storage_provider is 'aws'."
  default     = ""
}

variable "k8s_service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account for IRSA (created by workload-identity module)."
  default     = "aws-irsa-sa"
}

variable "sunbird_encryption_key" {
  type        = string
  description = "Migration-only: OLD cluster's sunbird_encryption_key, used by learn-service to decrypt migrated PII. Empty for fresh installs (learn-service falls back to random_string)."
  default     = ""
  sensitive   = true
}
