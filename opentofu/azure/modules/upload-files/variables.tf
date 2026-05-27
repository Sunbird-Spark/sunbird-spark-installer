variable "storage_account_name" {
    type        = string
    description = "Storage account name."
}

variable "storage_container_public" {
    type        = string
    description = "Public storage container name with blob access."
}


variable "public_artifacts_path" {
    type        = string
    description = "Absolute or relative path to the public-artifacts directory in the sunbird-spark-installer repo. Defaults to the repo root resolved from the module path."
    default     = ""
}

variable "sunbird_player_editor_tag" {
    type        = string
    description = "Git tag for Sunbird-Knowlg repos: sunbird-content-plugins, sunbird-content-editor, sunbird-generic-editor, sunbird-content-player."
    default     = "master"
}

variable "knowledge_platform_tag" {
    type        = string
    description = "Git branch/tag for the knowledge-platform repo (schemas/local upload)."
    default     = "master"
}
