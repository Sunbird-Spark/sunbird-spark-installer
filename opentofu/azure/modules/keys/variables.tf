variable "environment" {
    type        = string
    description = "environment name. All resources will be prefixed with this value."
}

variable "building_block" {
    type        = string
    description = "Building block name. All resources will be prefixed with this value."
}

variable "storage_account_name" {
    type        = string
    description = "Storage account name."
}

variable "storage_container_public" {
    type        = string
    description = "Public storage container name with blob access."
}

variable "storage_container_private" {
    type        = string
    description = "Private storage container name."
}

variable "base_location" {
    type        = string
    description = "Location of terrafrom execution folder."
}

variable "rsa_keys_count" {
    type        = number
    description = "Number of rsa keys to generate"
    default     = 2
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name to create the Key Vault in."
}

variable "location" {
  type        = string
  description = "Azure location to create the Key Vault in."
  default     = "Central India"
}

variable "aks_subnet_id" {
  type        = string
  description = "AKS subnet resource ID — allow-listed on the Key Vault firewall."
}

variable "runner_subnet_id" {
  type        = string
  description = "Runner VM subnet resource ID — allow-listed on the Key Vault firewall."
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password (from the random_passwords module) — mirrored into Key Vault."
  sensitive   = true
}

variable "superset_admin_password" {
  type        = string
  description = "Superset admin password (from the random_passwords module) — mirrored into Key Vault."
  sensitive   = true
}

variable "keycloak_password" {
  type        = string
  description = "Keycloak admin password (from the random_passwords module) — mirrored into Key Vault."
  sensitive   = true
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags for the resources. These tags will be applied to all the resources."
  default     = {}
}

