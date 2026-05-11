variable "base_location" {
  description = "Base location path"
  type        = string
}

variable "env" {
  description = "Environment abbreviation"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "building_block" {
  description = "Building block name"
  type        = string
}

variable "aws_storage_account_mail" {
  description = "AWS storage account email (IAM role ARN)"
  type        = string
}

variable "aws_storage_bucket_key" {
  description = "AWS storage bucket key/credential"
  type        = string
}

variable "storage_container_public" {
  description = "Public S3 bucket name"
  type        = string
}

variable "storage_container_private" {
  description = "Private S3 bucket name"
  type        = string
}

variable "dial_state_container_public" {
  description = "DIAL state public S3 bucket name"
  type        = string
}

variable "velero_storage_container_private" {
  description = "Velero backup S3 bucket name"
  type        = string
}

variable "random_string" {
  type        = string
  description = "This string will be used to encrypt / mask various values. Use a strong random string in order to secure the applications. The string should be between 12 and 24 characters in length. If you forget the string, the application will stop working and the string cannot be retrieved."
  validation {
    condition     = length(var.random_string) >= 12 && length(var.random_string) <= 24
    error_message = "The string must have a length ranging from 12 to 24 characters."
  }
}

variable "private_ingressgateway_ip" {
  description = "Private ingress gateway IP"
  type        = string
  default     = ""
}

variable "encryption_string" {
  description = "Encryption string"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "storage_class" {
  description = "Storage class for Kubernetes"
  type        = string
  default     = "gp2"
}

variable "cloud_storage_provider" {
  description = "Cloud storage provider"
  type        = string
  default     = "aws"
}

variable "cloud_storage_region" {
  description = "Cloud storage region"
  type        = string
}

variable "service_account_role_arn" {
  description = "Service account IAM role ARN"
  type        = string
}
