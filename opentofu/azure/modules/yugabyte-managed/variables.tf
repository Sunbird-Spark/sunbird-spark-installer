variable "environment" {
  type        = string
  description = "environment name. All resources will be prefixed with this value."
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Existing Azure resource group name (same one the AKS cluster is in)."
  type        = string
}

variable "location" {
  type        = string
  description = "Azure location to create the resources."
  default     = "Central India"
}

variable "yugabyte_region" {
  type        = string
  description = "YugabyteDB Aeon region code for the above Azure location, e.g. centralindia for Central India."
  default     = "centralindia"
}

variable "aks_vnet_name" {
  type        = string
  description = "Name of the existing AKS VNet (output of the network module) to link the private endpoint/DNS zone into."
}

variable "aks_subnet_id" {
  type        = string
  description = "Subnet ID inside the AKS VNet where the Azure Private Endpoint should be created."
}

variable "ybm_auth_token" {
  type        = string
  description = "YugabyteDB Aeon API key (account-level, from Usage & Billing > API Keys)."
  sensitive   = true
}

variable "ybm_host" {
  type        = string
  description = "YugabyteDB Aeon console host."
  default     = "cloud.yugabyte.com"
}

variable "db_username" {
  type        = string
  description = "Username for both YSQL and YCQL on the managed cluster."
  default     = "yugabyte"
}

variable "db_password" {
  type        = string
  description = "Password for both YSQL and YCQL on the managed cluster."
  sensitive   = true
}

variable "num_nodes" {
  type        = number
  description = "Number of nodes (matches current self-hosted RF3 topology: 3 nodes, AZ-level fault tolerance)."
  default     = 3
}

variable "num_cores" {
  type        = number
  description = "vCPUs per node."
  default     = 4
}

variable "disk_size_gb" {
  type        = number
  description = "Disk size per node, in GB."
  default     = 85
}

variable "security_principal" {
  type        = string
  description = "Azure subscription ID to grant access to the Private Service Endpoint (same as var.subscription_id unless the AKS cluster lives in a different subscription)."
  default     = ""
}
