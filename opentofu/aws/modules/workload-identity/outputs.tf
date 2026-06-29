output "iam_role_arn" {
  value       = aws_iam_role.workload_identity.arn
  description = "ARN of the IAM role for workload identity (IRSA)."
}

output "iam_role_name" {
  value       = aws_iam_role.workload_identity.name
  description = "Name of the IAM role for workload identity."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "ARN of the OIDC identity provider for EKS."
}

output "k8s_service_account_names" {
  value       = { for k, v in kubernetes_service_account.workload_identity : k => v.metadata[0].name }
  description = "Map of service account names created per key (sunbird, velero, etc.)."
}
