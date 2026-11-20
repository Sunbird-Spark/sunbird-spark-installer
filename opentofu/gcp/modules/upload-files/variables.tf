variable "storage_account_name" {
  type        = string
  description = "Storage account name (used in object URL)."
}

variable "storage_container_public" {
  type        = string
  description = "Public bucket name."
}

variable "public_artifacts_path" {
  type        = string
  description = "Absolute path to the public-artifacts directory. Pass get_repo_root()/public-artifacts from Terragrunt."
}

variable "sunbird_player_editor_ref" {
  type        = string
  description = "Git tag for Sunbird-Knowlg repos: sunbird-content-plugins, sunbird-content-editor, sunbird-generic-editor, sunbird-content-player."
  default     = "master"

  # Interpolated unquoted into local-exec git/docker commands below -- restrict
  # to characters valid in a git ref to close off shell injection via this
  # operator-editable global-values.yaml value.
  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.sunbird_player_editor_ref))
    error_message = "sunbird_player_editor_ref must only contain letters, numbers, dots, underscores, hyphens, and slashes (a valid git branch/tag name)."
  }
}

variable "knowledge_platform_ref" {
  type        = string
  description = "Git branch or tag for the knowledge-platform repo (schemas/local upload)."
  default     = "master"

  # Same reasoning as sunbird_player_editor_ref above.
  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.knowledge_platform_ref))
    error_message = "knowledge_platform_ref must only contain letters, numbers, dots, underscores, hyphens, and slashes (a valid git branch/tag name)."
  }
}
