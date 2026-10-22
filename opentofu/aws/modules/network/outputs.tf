output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "eks_subnet_ids" {
  value = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
  description = "All subnet IDs (private + public) for EKS cluster and node group."
}

output "eks_node_security_group_id" {
  value = aws_security_group.eks_nodes.id
}
