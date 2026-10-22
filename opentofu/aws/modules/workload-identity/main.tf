terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

provider "kubernetes" {
  host                   = var.kubernetes_host
  cluster_ca_certificate = var.kubernetes_cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

locals {
  environment_name = "${var.building_block}-${var.environment}"
  # Strip the leading "https://" from the OIDC issuer URL for use in ARNs
  oidc_issuer_host = replace(var.oidc_issuer_url, "https://", "")
}

# OIDC Provider for the EKS cluster (enables IAM Roles for Service Accounts / IRSA)
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.oidc_thumbprint]
  url             = var.oidc_issuer_url

  tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
}

# IAM policy for S3 access (least-privilege: read/write/delete objects, no bucket management)
resource "aws_iam_policy" "s3_workload_policy" {
  name        = "${local.environment_name}-s3-workload-policy"
  description = "Least-privilege S3 access for Sunbird workloads. Allows object read/write/delete on designated buckets only."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:CopyObject",
          "s3:ListBucket",
        ]
        Resource = concat(
          [for arn in var.bucket_arns : arn],
          [for arn in var.bucket_arns : "${arn}/*"]
        )
      },
      {
        Sid    = "S3PresignedUrl"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
        ]
        Resource = [for arn in var.bucket_arns : arn]
      }
    ]
  })
}

# IAM role for Sunbird workloads (IRSA)
resource "aws_iam_role" "workload_identity" {
  name = "${local.environment_name}-workload-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for sa_key, sa in var.k8s_service_accounts : {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_host}:sub" = "system:serviceaccount:${sa.namespace}:${sa.name}"
            "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
}

resource "aws_iam_role_policy_attachment" "workload_identity_s3" {
  role       = aws_iam_role.workload_identity.name
  policy_arn = aws_iam_policy.s3_workload_policy.arn
}

# Kubernetes namespaces
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.k8s_namespaces)
  metadata {
    name = each.value
  }
}

# Kubernetes service accounts with IRSA annotation
resource "kubernetes_service_account" "workload_identity" {
  for_each = var.k8s_service_accounts

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
    labels = {
      "eks.amazonaws.com/use" = "true"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.workload_identity.arn
    }
  }

  depends_on = [
    aws_iam_role.workload_identity,
    aws_iam_openid_connect_provider.eks,
    kubernetes_namespace.namespaces,
  ]
}
