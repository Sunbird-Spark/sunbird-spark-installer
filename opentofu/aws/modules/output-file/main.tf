locals {
  global_values_cloud_file = "${var.base_location}/../global-cloud-values.yaml"
}

resource "local_sensitive_file" "global_cloud_values_yaml" {
  content = templatefile("${path.module}/global-cloud-values.yaml.tfpl", {
    env                                  = var.env,
    environment                          = var.environment,
    building_block                       = var.building_block,
    aws_storage_account_email            = var.aws_storage_account_mail,
    aws_storage_account_key              = var.aws_storage_bucket_key,
    aws_public_container_name            = var.storage_container_public,
    aws_private_container_name           = var.storage_container_private,
    aws_dial_state_container_public      = var.dial_state_container_public,
    aws_velero_storage_container_private = var.velero_storage_container_private,
    random_string                        = var.random_string,
    private_ingressgateway_ip            = var.private_ingressgateway_ip,
    encryption_string                    = var.encryption_string,
    aws_account_id                       = var.aws_account_id
    storage_class                        = var.storage_class
    cloud_storage_provider               = var.cloud_storage_provider
    cloud_storage_region                 = var.cloud_storage_region
    service_account_role_arn             = var.service_account_role_arn
  })
  filename = local.global_values_cloud_file
}

resource "null_resource" "upload_global_cloud_values_yaml" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.global_values_cloud_file} s3://${var.storage_container_private}/${var.environment}-global-cloud-values.yaml"
  }
  depends_on = [local_sensitive_file.global_cloud_values_yaml]
}
