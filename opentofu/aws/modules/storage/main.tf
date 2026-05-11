data "aws_caller_identity" "current" {}

resource "random_id" "bucket_id" {
  byte_length = 5
}

locals {
  unique_uuid = random_id.bucket_id.hex

  common_tags = {
    Environment    = var.environment
    BuildingBlock  = var.building_block
    UniqueUuid     = local.unique_uuid
  }

  environment_name = "${var.building_block}-${var.environment}"
}

# Public S3 bucket for public assets
resource "aws_s3_bucket" "storage_container_public" {
  bucket        = "${local.environment_name}-public-${local.unique_uuid}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-public"
  })
}

resource "aws_s3_bucket_versioning" "storage_container_public" {
  bucket = aws_s3_bucket.storage_container_public.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "storage_container_public" {
  bucket = aws_s3_bucket.storage_container_public.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "storage_container_public" {
  bucket = aws_s3_bucket.storage_container_public.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.storage_container_public.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.storage_container_public]
}

resource "aws_s3_bucket_cors_configuration" "storage_container_public" {
  bucket = aws_s3_bucket.storage_container_public.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["https://${var.domain}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Private S3 bucket
resource "aws_s3_bucket" "storage_container_private" {
  bucket        = "${local.environment_name}-private-${local.unique_uuid}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-private"
  })
}

resource "aws_s3_bucket_versioning" "storage_container_private" {
  bucket = aws_s3_bucket.storage_container_private.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "storage_container_private" {
  bucket = aws_s3_bucket.storage_container_private.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DIAL state public bucket
resource "aws_s3_bucket" "dial_state_container_public" {
  bucket        = "${local.environment_name}-dial-${local.unique_uuid}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-dial"
  })
}

resource "aws_s3_bucket_versioning" "dial_state_container_public" {
  bucket = aws_s3_bucket.dial_state_container_public.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dial_state_container_public" {
  bucket = aws_s3_bucket.dial_state_container_public.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "dial_state_container_public" {
  bucket = aws_s3_bucket.dial_state_container_public.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.dial_state_container_public.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.dial_state_container_public]
}

resource "aws_s3_bucket_cors_configuration" "dial_state_container_public" {
  bucket = aws_s3_bucket.dial_state_container_public.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["https://${var.domain}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Velero backup bucket (private)
resource "aws_s3_bucket" "velero_storage_container_private" {
  bucket        = "${local.environment_name}-velero-private-${local.unique_uuid}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.environment_name}-velero"
  })
}

resource "aws_s3_bucket_versioning" "velero_storage_container_private" {
  bucket = aws_s3_bucket.velero_storage_container_private.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "velero_storage_container_private" {
  bucket = aws_s3_bucket.velero_storage_container_private.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
