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

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_network" {
  description = "Whether to create network resources"
  type        = bool
  default     = true
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways to create (1 for dev, 2 for HA)"
  type        = number
  default     = 1
  validation {
    condition     = var.nat_gateway_count >= 1 && var.nat_gateway_count <= 3
    error_message = "NAT gateway count must be between 1 and 3."
  }
}

variable "availability_zone_count" {
  description = "Number of Availability Zones to use (2-3, EKS requires minimum 2 AZs)"
  type        = number
  default     = 2
  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be between 2 and 3 (EKS requires minimum 2 AZs)."
  }
}
