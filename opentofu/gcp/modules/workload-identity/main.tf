terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

provider "google" {
  project = var.project
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${var.kubernetes_host}"
  cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

locals {
  environment_name = "${var.building_block}-${var.environment}"

  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
}

# ── GCP Service Account ──────────────────────────────────────────────────
resource "google_service_account" "service_account" {
  project      = var.project
  account_id   = local.environment_name
  display_name = var.cluster_service_account_description
}

# ── Operational roles for the SA (least-priv: logging/monitoring only) ───
resource "google_project_iam_member" "service_account_roles" {
  for_each = toset(var.service_account_roles)

  project = var.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

# ── Custom role: object-only bucket operations (no bucket admin) ─────────
resource "google_project_iam_custom_role" "bucket_object_operator" {
  project     = var.project
  role_id     = replace("${local.environment_name}_bucket_object_operator", "-", "_")
  title       = "${local.environment_name} Bucket Object Operator"
  description = "Object-level read/write on managed buckets. No bucket admin."
  stage       = "GA"

  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
  ]
}

# ── Bucket-scoped IAM bindings (one per bucket) ──────────────────────────
resource "google_storage_bucket_iam_member" "bucket_access" {
  for_each = toset(var.container_names)

  bucket = each.value
  role   = google_project_iam_custom_role.bucket_object_operator.id
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# ── Workload Identity binding: K8s SA -> GCP SA ──────────────────────────
resource "google_service_account_iam_member" "workload_identity_binding" {
  for_each = {
    for k, v in var.service_account_bindings : k => v
    if v == true
  }

  service_account_id = google_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[${each.key}]"
}

# ── K8s namespaces ───────────────────────────────────────────────────────
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.k8s_namespaces)

  metadata {
    name = each.value
  }
}

# ── K8s service accounts annotated for Workload Identity ─────────────────
resource "kubernetes_service_account" "workload_identity" {
  for_each = var.k8s_service_accounts

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.service_account.email
    }
  }

  depends_on = [
    kubernetes_namespace.namespaces,
    google_service_account_iam_member.workload_identity_binding,
  ]
}
