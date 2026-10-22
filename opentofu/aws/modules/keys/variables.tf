variable "environment" {
    type        = string
    description = "environment name. All resources will be prefixed with this value."
}

variable "building_block" {
    type        = string
    description = "Building block name. All resources will be prefixed with this value."
}

variable "storage_bucket_private" {
    type        = string
    description = "Private S3 bucket name."
}

variable "storage_bucket_public" {
    type        = string
    description = "Public S3 bucket name."
}

variable "base_location" {
    type        = string
    description = "Location of terraform execution folder."
}

variable "rsa_keys_count" {
    type        = number
    description = "Number of rsa keys to generate"
    default     = 2
}
