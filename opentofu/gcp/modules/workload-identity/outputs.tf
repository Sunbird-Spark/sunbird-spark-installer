output "service_account_email" {
  value       = google_service_account.service_account.email
  description = "Email of the GCP service account used by Workload Identity."
}

output "service_account_name" {
  value       = google_service_account.service_account.name
  description = "Fully-qualified name of the GCP service account."
}

output "k8s_service_account_names" {
  value       = { for k, v in var.k8s_service_accounts : k => v.name }
  description = "Map of K8s service account names created in their namespaces."
}
