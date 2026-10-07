variable "s3_bucket_public" {
  type        = string
  description = "Public S3 bucket name."
}

variable "aws_region" {
  type        = string
  description = "AWS region where the S3 buckets reside."
  default     = "ap-south-1"
}

variable "public_artifacts_path" {
  type        = string
  description = "Absolute path to the public-artifacts directory. Pass get_repo_root()/public-artifacts from Terragrunt."
}

variable "sunbird_player_editor_ref" {
  type        = string
  description = "Git tag for Sunbird-Knowlg repos: sunbird-content-plugins, sunbird-content-editor, sunbird-generic-editor, sunbird-content-player."
  default     = "master"
}

variable "knowledge_platform_ref" {
  type        = string
  description = "Git branch or tag for the knowledge-platform repo (schemas/local upload)."
  default     = "master"
}
