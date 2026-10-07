terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "random_id" "bucket_id" {
  byte_length = 5
}

locals {
  unique_id        = random_id.bucket_id.hex
  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
    unique_id     = local.unique_id
  }
  environment_name = "${var.building_block}-${var.environment}"
}

# Public S3 bucket (equivalent to Azure public container with blob access)
resource "aws_s3_bucket" "public" {
  bucket = "${local.environment_name}-public-${local.unique_id}"

  tags = merge(local.common_tags, var.additional_tags)
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.public.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_cors_configuration" "public" {
  bucket = aws_s3_bucket.public.id

  cors_rule {
    max_age_seconds = 200
    allowed_origins = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    expose_headers  = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods"]
    allowed_headers = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Origin", "Content-Type"]
  }
}

resource "aws_s3_bucket_policy" "public" {
  bucket     = aws_s3_bucket.public.id
  depends_on = [aws_s3_bucket_public_access_block.public]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.public.arn}/*"
      }
    ]
  })
}

# Private S3 bucket (equivalent to Azure private container)
resource "aws_s3_bucket" "private" {
  bucket = "${local.environment_name}-private-${local.unique_id}"

  tags = merge(local.common_tags, var.additional_tags)
}

resource "aws_s3_bucket_public_access_block" "private" {
  bucket = aws_s3_bucket.private.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Velero S3 bucket (equivalent to Azure velero private container)
resource "aws_s3_bucket" "velero" {
  bucket = "${local.environment_name}-velero-${local.unique_id}"

  tags = merge(local.common_tags, var.additional_tags)
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
