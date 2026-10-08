
# Service account creation
locals {
  create_sa_binding         = (var.cluster_service_account_name == "" || var.sa_namespace == "") ? false : true
  all_service_account_roles = var.service_account_roles
  common_tags = {
        environment = "${var.environment}"
        BuildingBlock = "${var.building_block}"
      }
      environment_name = "${var.building_block}-${var.environment}"
}

resource "google_service_account" "service_account" {
  project      = var.project
  account_id   = local.environment_name
  display_name = var.cluster_service_account_description
}

# Assign roles to the service account
resource "google_project_iam_member" "service_account-roles" {
  for_each = toset(local.all_service_account_roles)

  project = var.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

# Object-level access on just the buckets this environment owns -- not
# project-wide roles/storage.admin, which also grants bucket create/delete
# and IAM-policy changes on every bucket in the project, including ones
# unrelated to this environment.
#
# roles/storage.objectAdmin is still the minimal built-in role for this: this
# SA both uploads (upload-files/output-file modules, runtime GCP-storage
# services) and overwrites/removes stale objects, so read-only
# (objectViewer) and write-only (objectCreator, can't overwrite or delete)
# aren't enough -- objectAdmin is the narrowest GCS role covering all three,
# and it's already scoped per-bucket via `bucket =` below, not project-wide.
resource "google_storage_bucket_iam_member" "storage_object_admin" {
  for_each = toset([
    var.sa_key_store_bucket,
    var.public_bucket,
    var.dial_state_bucket,
    var.velero_bucket,
  ])

  bucket = each.value
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Assign Workload Identity User role to service account (optional)
resource "google_service_account_iam_member" "workload_identity_role" {
  for_each = {
    for k, v in var.service_account_bindings : k => v
    if v == true
  }

  service_account_id = google_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[${each.key}]"
}


# Create a service account key
# Generate a service account key
resource "google_service_account_key" "service_account" {
  service_account_id = google_service_account.service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Save key to local file
resource "local_file" "service_account" {
  content  = base64decode(google_service_account_key.service_account.private_key)
  filename = "${path.module}/sa-keys/${local.environment_name}.json"
}

# Upload the key to GCS
# Upload the key to GCS
resource "google_storage_bucket_object" "gke_service_account" {
  name   = "service-accounts/${local.environment_name}.json"
  source = local_file.service_account.filename
  bucket = var.sa_key_store_bucket

  lifecycle {
    ignore_changes = [
      crc32c,
      md5hash,
      generation
    ]
  }
}

