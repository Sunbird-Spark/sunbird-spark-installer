variable "environment" {
  type        = string
  description = "Environment name."
}

variable "building_block" {
  type        = string
  description = "Building block name."
}

variable "location" {
  type        = string
  description = "Azure location."
  default     = "Central India"
}

variable "resource_group_name" {
  type        = string
  description = "Azure resource group name."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "runner_subnet_id" {
  type        = string
  description = "Subnet ID for the runner VM."
}

variable "vm_size" {
  type        = string
  description = "VM size for the runner."
  default     = "Standard_B2s"
}

variable "vm_admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "vm_ssh_public_key" {
  type        = string
  description = "SSH public key for VM admin access."
}

variable "github_runner_token" {
  type        = string
  description = "GitHub Actions runner registration token."
  sensitive   = true
}

variable "github_org" {
  type        = string
  description = "GitHub organization name."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name. Leave empty for org-level runner."
  default     = ""
}

variable "pritunl_vpn_network" {
  type        = string
  description = "VPN client IP pool for Pritunl."
  default     = "172.16.0.0/24"
}

variable "pritunl_org_name" {
  type        = string
  description = "Pritunl organization name."
  default     = "sunbird-spark"
}

variable "pritunl_users" {
  type = list(object({
    name  = string
    email = string
  }))
  description = "List of VPN users to create in Pritunl."
  default     = []
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags for resources."
  default     = {}
}
