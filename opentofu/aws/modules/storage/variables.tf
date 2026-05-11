variable "environment" {
  description = "Environment name"
  type        = string
}

variable "building_block" {
  description = "Building block name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "domain" {
  description = "Domain name for CORS configuration"
  type        = string
}

variable "env" {
  description = "Environment abbreviation"
  type        = string
}
