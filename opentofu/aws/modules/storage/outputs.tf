output "s3_bucket_public" {
  value = aws_s3_bucket.public.id
  description = "Name of the public S3 bucket."
}

output "s3_bucket_private" {
  value = aws_s3_bucket.private.id
  description = "Name of the private S3 bucket."
}

output "s3_bucket_velero" {
  value = aws_s3_bucket.velero.id
  description = "Name of the Velero S3 bucket."
}

output "s3_bucket_public_arn" {
  value = aws_s3_bucket.public.arn
}

output "s3_bucket_private_arn" {
  value = aws_s3_bucket.private.arn
}

output "s3_bucket_velero_arn" {
  value = aws_s3_bucket.velero.arn
}
