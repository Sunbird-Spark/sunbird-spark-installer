output "public_bucket_name" {
  description = "Name of the public S3 bucket"
  value       = aws_s3_bucket.storage_container_public.id
}

output "public_bucket_arn" {
  description = "ARN of the public S3 bucket"
  value       = aws_s3_bucket.storage_container_public.arn
}

output "private_bucket_name" {
  description = "Name of the private S3 bucket"
  value       = aws_s3_bucket.storage_container_private.id
}

output "private_bucket_arn" {
  description = "ARN of the private S3 bucket"
  value       = aws_s3_bucket.storage_container_private.arn
}

output "dial_bucket_name" {
  description = "Name of the DIAL state public S3 bucket"
  value       = aws_s3_bucket.dial_state_container_public.id
}

output "dial_bucket_arn" {
  description = "ARN of the DIAL state public S3 bucket"
  value       = aws_s3_bucket.dial_state_container_public.arn
}

output "velero_bucket_name" {
  description = "Name of the Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_storage_container_private.id
}

output "velero_bucket_arn" {
  description = "ARN of the Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_storage_container_private.arn
}

output "unique_uuid" {
  description = "Unique UUID for resource naming"
  value       = local.unique_uuid
}
