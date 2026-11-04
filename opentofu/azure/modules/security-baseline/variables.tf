variable "environment" {
  type        = string
  description = "environment name. All resources will be prefixed with this value."
}

variable "building_block" {
  type        = string
  description = "Building block name. All resources will be prefixed with this value."
}

variable "location" {
  type        = string
  description = "Azure location to create the resources."
  default     = "Central India"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags for the resources. These tags will be applied to all the resources."
  default     = {}
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name to create the activity-log workspace in."
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

# Added: retention window for the subscription Activity Log workspace.
variable "log_retention_days" {
  type        = number
  description = "Retention window (days) for the subscription Activity Log workspace."
  default     = 30
}
