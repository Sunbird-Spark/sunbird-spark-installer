variable "storage_account_name" {
  type        = string
  description = "Storage account name (used in object URL)."
}

variable "storage_container_public" {
  type        = string
  description = "Public bucket name."
}

variable "project_number" {
  type        = string
  description = "GCP project number used by rclone gcs backend."
}

variable "sunbird_public_artifacts_account" {
  type        = string
  description = "Public account holding sunbird release artifacts."
  default     = "downloadableartifacts"
}

variable "sunbird_public_artifacts_account_sas_url" {
  type        = string
  description = "Read-only SAS URL for the sunbird public account."
  default     = "https://downloadableartifacts.blob.core.windows.net/?sv=2022-11-02&ss=bf&srt=co&sp=rlitfx&se=2026-08-30T20:37:29Z&st=2024-07-10T12:37:29Z&spr=https&sig=hcXksbrbR%2BJgCB0EKxiwHCSsQ6r2eSlyOVnqnjxFOH0%3D"
}

variable "sunbird_public_artifacts_container" {
  type        = string
  description = "Release-specific container holding artifacts."
  default     = "release700"
}
