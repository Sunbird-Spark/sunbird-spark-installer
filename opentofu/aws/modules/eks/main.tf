terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
  environment_name = "${var.building_block}-${var.environment}"
}

# IAM role for the EKS cluster control plane
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.environment_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, var.additional_tags)
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# EKS Cluster
resource "aws_eks_cluster" "eks" {
  name     = local.environment_name
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = false
    endpoint_private_access = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(local.common_tags, var.additional_tags)

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# IAM role for EKS node group
resource "aws_iam_role" "eks_node_role" {
  name = "${local.environment_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, var.additional_tags)
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_read" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_ebs_csi_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "aws-ebs-csi-driver"
  tags         = merge(local.common_tags, var.additional_tags)
  depends_on   = [aws_eks_node_group.big_nodepool, aws_iam_role_policy_attachment.eks_ebs_csi_policy]
}

# Launch template enforcing IMDSv2 on all nodes and setting required ulimits
resource "aws_launch_template" "big_nodepool" {
  name_prefix = "${local.environment_name}-big-nodepool-"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "* soft nofile 1048576" >> /etc/security/limits.conf
    echo "* hard nofile 1048576" >> /etc/security/limits.conf
    echo "fs.file-max = 1048576" >> /etc/sysctl.conf
    sysctl -p
  EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.imdsv2_http_hop_limit
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, var.additional_tags)
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, var.additional_tags)
  }

  tags = merge(local.common_tags, var.additional_tags)
}

# EKS Node Group (equivalent to AKS default node pool)
resource "aws_eks_node_group" "big_nodepool" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.big_nodepool_name
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.big_node_size]

  launch_template {
    id      = aws_launch_template.big_nodepool.id
    version = aws_launch_template.big_nodepool.latest_version
  }

  scaling_config {
    desired_size = var.big_node_count
    min_size     = 1
    max_size     = var.big_node_count + 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.common_tags, var.additional_tags)

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_read,
  ]
}

# Update kubeconfig after cluster creation
resource "null_resource" "kubeconfig" {
  triggers = {
    cluster_id      = aws_eks_cluster.eks.id
    cluster_version = aws_eks_cluster.eks.version
    always_run      = timestamp()
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks.name} --kubeconfig ~/.kube/config"
  }

  depends_on = [aws_eks_cluster.eks, aws_eks_node_group.big_nodepool]
}
