resource "local_sensitive_file" "rclone_config" {
  content = templatefile("${path.module}/config.tfpl", {
    aws_access_key_id                            = var.aws_access_key_id
    aws_secret_access_key                        = var.aws_secret_access_key
    region                                       = var.region
    sunbird_public_artifacts_bucket              = var.sunbird_public_artifacts_bucket
    sunbird_public_artifacts_access_key_id       = var.sunbird_public_artifacts_access_key_id
    sunbird_public_artifacts_secret_access_key   = var.sunbird_public_artifacts_secret_access_key
    sunbird_public_artifacts_account             = var.sunbird_public_artifacts_account
    sunbird_public_artifacts_account_sas_url     = var.sunbird_public_artifacts_account_sas_url
    sunbird_public_artifacts_container           = var.sunbird_public_artifacts_container
  })
  filename = pathexpand("~/.config/rclone/rclone.conf")
}

resource "null_resource" "copy_from_sunbird_bucket" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "rclone copy sunbird:${var.sunbird_public_artifacts_container} ownaccount:${var.storage_container_public} --transfers 600 --checkers 600 --exclude .terragrunt-source-manifest"
  }
  depends_on = [local_sensitive_file.rclone_config]
}

locals {
  # Check if sunbird-rc/schemas directory exists using try()
  schemas_dir = "${path.module}/sunbird-rc/schemas"
  template_files = try(fileset(local.schemas_dir, "*.json"), [])
}

resource "local_file" "output_files" {
  for_each = toset(local.template_files)
  content = templatefile("${path.module}/sunbird-rc/schemas/${each.value}", {
    cloud_storage_schema_url = "https://${var.storage_account_name}.s3.${var.region}.amazonaws.com/${var.storage_container_public}"
  })
  filename = "${path.module}/sunbird-rc/schemas/${each.value}"
}

resource "null_resource" "upload_rc_schemas_to_public_bucket" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "rclone copy ${path.module}/sunbird-rc/schemas ownaccount:${var.storage_container_public}/schemas --transfers 25 --checkers 25 --exclude .terragrunt-source-manifest"
  }
  depends_on = [local_sensitive_file.rclone_config]
}
