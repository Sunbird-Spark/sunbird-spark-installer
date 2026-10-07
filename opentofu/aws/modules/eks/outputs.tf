output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "kubernetes_host" {
  value     = aws_eks_cluster.eks.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  sensitive = true
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

output "private_ingressgateway_ip" {
  value = var.private_ingressgateway_ip
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node_role.arn
}
