variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "storage_container_public" {
  description = "Public S3 bucket name"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name"
  type        = string
}

variable "sunbird_public_artifacts_bucket" {
  description = "Sunbird public artifacts bucket name"
  type        = string
}

variable "sunbird_public_artifacts_access_key_id" {
  description = "Sunbird public artifacts access key ID"
  type        = string
  sensitive   = true
}

variable "sunbird_public_artifacts_secret_access_key" {
  description = "Sunbird public artifacts secret access key"
  type        = string
  sensitive   = true
}

variable "sunbird_public_artifacts_account" {
    type        = string
    description = "The public account name where storage artifacts are published for this release."
    default     = "downloadableartifacts"
}

variable "sunbird_public_artifacts_account_sas_url" {
    type        = string
    description = "The readonly sas token url for the sunbird public account."
    default     = "https://downloadableartifacts.blob.core.windows.net/?se=2030-12-31T23%3A59%3A00Z&sp=rxlft&spr=https&sv=2022-11-02&ss=fb&srt=sco&sig=9IDJq3H94oluxYUwB2M1SxwjdvpVvYzKMgAJHomrjuY%3D"
}

variable "sunbird_public_artifacts_container" {
    type        = string
    description = "The container name dedicated for this release which holds the storage artifatcs."
    default     = "release700"
}

