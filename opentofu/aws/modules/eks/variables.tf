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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "c5a.4xlarge"
}

variable "node_disk_size_gb" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100
}

variable "desired_node_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 6
}

variable "min_node_count" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 4
}

variable "max_node_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "disable_public_endpoint" {
  description = "Whether to disable public API endpoint"
  type        = bool
  default     = false
}

variable "enabled_cluster_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = []
}

variable "ebs_csi_driver_version" {
  description = "Version of AWS EBS CSI driver addon"
  type        = string
  default     = "v1.25.0-eksbuild.1"
}

variable "vpc_cni_version" {
  description = "Version of VPC CNI addon"
  type        = string
  default     = "v1.15.5-eksbuild.1"
}

variable "coredns_version" {
  description = "Version of CoreDNS addon"
  type        = string
  default     = "v1.10.1-eksbuild.6"
}

variable "kube_proxy_version" {
  description = "Version of kube-proxy addon"
  type        = string
  default     = "v1.28.2-eksbuild.2"
}
