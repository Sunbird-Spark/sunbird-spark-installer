terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
  environment_name = "${var.building_block}-${var.environment}"

  # Use the first 3 AZs (or fewer if the region has less than 3)
  az_count = min(3, length(data.aws_availability_zones.available.names))
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = local.environment_name
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-igw"
    }
  )
}

# Public subnets (one per AZ) — used for load balancers / NAT gateways
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name                                         = "${local.environment_name}-public-${local.azs[count.index]}"
      "kubernetes.io/role/elb"                     = "1"
      "kubernetes.io/cluster/${local.environment_name}" = "shared"
    }
  )
}

# Private subnets (one per AZ) — used for EKS nodes
resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + local.az_count)
  availability_zone = local.azs[count.index]

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name                                         = "${local.environment_name}-private-${local.azs[count.index]}"
      "kubernetes.io/role/internal-elb"            = "1"
      "kubernetes.io/cluster/${local.environment_name}" = "shared"
    }
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = local.az_count
  domain = "vpc"

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-nat-eip-${count.index}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways (one per public subnet for HA)
resource "aws_nat_gateway" "main" {
  count         = local.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-nat-${count.index}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-public-rt"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables (one per AZ, routes to NAT GW in same AZ)
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-private-rt-${count.index}"
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group for EKS nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${local.environment_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow all intra-node traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name = "${local.environment_name}-eks-nodes-sg"
    }
  )
}
