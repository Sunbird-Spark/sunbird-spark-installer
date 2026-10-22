variable "environment" {
  type        = string
  description = "Environment name. All resources will be prefixed with this value."
}

variable "building_block" {
  type        = string
  description = "Building block name. All resources will be prefixed with this value."
}

variable "region" {
  type        = string
  description = "AWS region to create the resources."
  default     = "ap-south-1"
}

variable "eks_version" {
  type        = string
  description = "EKS Kubernetes version to pin. Check available versions with: aws eks describe-addon-versions"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the EKS cluster and node group."
}

variable "big_nodepool_name" {
  type        = string
  description = "Big node pool name."
  default     = "bigpool"
}

variable "big_node_count" {
  type        = number
  description = "Big node pool node count."
  default     = 2
}

variable "big_node_size" {
  type        = string
  description = "Big node pool EC2 instance type."
  default     = "t3.xlarge"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags for the resources. These tags will be applied to all the resources."
  default     = {}
}

variable "private_ingressgateway_ip" {
  type        = string
  description = "Nginx private ingress IP (reserved for reference, not pre-created on AWS)."
  default     = "10.0.0.10"
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach EKS API server. Restrict to office/VPN IPs in production."
  default     = ["0.0.0.0/0"]
}

variable "imdsv2_http_hop_limit" {
  type        = number
  description = "IMDSv2 hop limit. 1 for EC2 instances, 2 for containerized workloads."
  default     = 2
}

