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
  description = "AWS region."
  default     = "ap-south-1"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (used for aws eks get-token in Kubernetes provider)."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the EKS cluster (from eks module output)."
}

variable "oidc_thumbprint" {
  type        = string
  description = "TLS thumbprint for the EKS OIDC provider. Obtain with: openssl s_client -connect <oidc-host>:443 | openssl x509 -fingerprint -noout"
  default     = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
}

variable "kubernetes_host" {
  type        = string
  description = "Kubernetes API server host (EKS cluster endpoint)."
}

variable "kubernetes_cluster_ca_certificate" {
  type        = string
  description = "Kubernetes cluster CA certificate (base64 decoded PEM)."
  sensitive   = true
}

variable "bucket_arns" {
  type        = list(string)
  description = "List of S3 bucket ARNs to grant workload access to."
  default     = []
}

variable "k8s_namespaces" {
  type        = list(string)
  description = "List of Kubernetes namespaces to create."
  default     = ["sunbird", "velero"]
}

variable "k8s_service_accounts" {
  type = map(object({
    namespace = string
    name      = string
  }))
  description = "Map of Kubernetes service accounts to create per namespace."
  default = {
    sunbird = {
      namespace = "sunbird"
      name      = "aws-irsa-sa"
    }
    velero = {
      namespace = "velero"
      name      = "aws-irsa-sa"
    }
  }
}
