# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED MODULE PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Environment name. All resources will be prefixed with this value."
}

variable "building_block" {
  type        = string
  description = "Building block name. All resources will be prefixed with this value."
}

variable "project" {
  type        = string
  description = "GCP project ID."
}

variable "container_names" {
  type        = list(string)
  description = "List of GCS bucket names to grant object-level access on."
}

variable "kubernetes_host" {
  type        = string
  description = "GKE cluster endpoint (host) for the kubernetes provider."
}

variable "kubernetes_cluster_ca_certificate" {
  type        = string
  description = "GKE cluster CA certificate (base64-encoded) for the kubernetes provider."
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------
variable "cluster_service_account_description" {
  type        = string
  description = "Description of the GCP service account."
  default     = "GKE Workload Identity service account managed by Terraform"
}

variable "service_account_roles" {
  type        = list(string)
  description = "Project-scope roles granted to the GCP service account."
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]
}

variable "service_account_bindings" {
  type        = map(bool)
  description = "Map of '<namespace>/<k8s-sa-name>' -> bool. true entries get a workloadIdentityUser binding."
  default = {
    "sunbird/sunbird-sa" = true
    "velero/velero-sa"   = true
  }
}

variable "k8s_namespaces" {
  type        = list(string)
  description = "Kubernetes namespaces to create."
  default     = ["sunbird", "velero"]
}

variable "k8s_service_accounts" {
  type = map(object({
    namespace = string
    name      = string
  }))
  description = "Map of K8s service accounts to create, annotated for Workload Identity."
  default = {
    sunbird = {
      namespace = "sunbird"
      name      = "sunbird-sa"
    }
    velero = {
      namespace = "velero"
      name      = "velero-sa"
    }
  }
}
