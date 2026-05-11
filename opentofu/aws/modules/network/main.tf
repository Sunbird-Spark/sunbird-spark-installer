# ---------------------------------------------------------------------------------------------------------------------
# Create VPC and Subnets
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common_tags = {
    Environment   = var.environment
    BuildingBlock = var.building_block
  }
  environment_name = "${var.building_block}-${var.environment}"
  
  # Limit to configured number of AZs
  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name                                              = "${local.environment_name}-vpc"
    "kubernetes.io/cluster/${local.environment_name}" = "shared"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = var.create_network ? length(local.azs) : 0
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                              = "${local.environment_name}-public-${local.azs[count.index]}"
    "kubernetes.io/cluster/${local.environment_name}" = "shared"
    "kubernetes.io/role/elb"                          = "1"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.create_network ? length(local.azs) : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 4, count.index + length(local.azs))
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name                                              = "${local.environment_name}-private-${local.azs[count.index]}"
    "kubernetes.io/cluster/${local.environment_name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = "1"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = var.create_network ? min(var.nat_gateway_count, var.availability_zone_count) : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count         = var.create_network ? min(var.nat_gateway_count, var.availability_zone_count) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-public-rt"
  })
}

# Public Route Table Association
resource "aws_route_table_association" "public" {
  count          = var.create_network ? length(aws_subnet.public) : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables
resource "aws_route_table" "private" {
  count  = var.create_network ? length(local.azs) : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index % min(var.nat_gateway_count, var.availability_zone_count)].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-private-rt-${count.index + 1}"
  })
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count          = var.create_network ? length(local.azs) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Group for allowing HTTP/HTTPS
resource "aws_security_group" "allow_http_https" {
  name        = "${local.environment_name}-allow-http-https"
  description = "Allow HTTP and HTTPS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-allow-http-https"
  })
}
