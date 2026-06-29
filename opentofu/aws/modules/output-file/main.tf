terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  global_values_cloud_file = "${var.base_location}/../global-cloud-values.yaml"
}

resource "local_sensitive_file" "global_cloud_values_yaml" {
  lifecycle {
    precondition {
      condition     = !(var.cloud_storage_provider == "aws" && var.aws_iam_role_arn == "")
      error_message = "aws_iam_role_arn must be provided when cloud_storage_provider is aws."
    }
  }

  content = templatefile("${path.module}/global-cloud-values.yaml.tfpl", {
    env                          = var.env,
    environment                  = var.environment,
    building_block               = var.building_block,
    aws_region                   = var.aws_region,
    aws_s3_bucket_public         = var.s3_bucket_public,
    aws_s3_bucket_private        = var.s3_bucket_private,
    aws_s3_bucket_velero         = var.s3_bucket_velero,
    private_ingressgateway_ip    = var.private_ingressgateway_ip,
    random_string                = var.random_string,
    cloud_storage_provider       = var.cloud_storage_provider,
    aws_iam_role_arn             = var.aws_iam_role_arn,
    k8s_service_account_name     = var.k8s_service_account_name,
    sunbird_encryption_key       = var.sunbird_encryption_key
  })
  filename = local.global_values_cloud_file
}

resource "null_resource" "upload_global_cloud_values_yaml" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.global_values_cloud_file} s3://${var.s3_bucket_private}/${var.environment}-global-cloud-values.yaml"
  }
  depends_on = [local_sensitive_file.global_cloud_values_yaml]
}
