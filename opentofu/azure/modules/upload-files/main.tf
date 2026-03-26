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
  template_files        = fileset("${path.module}/sunbird-rc/schemas", "*.json")
  sas_query             = split("?", var.sunbird_public_artifacts_account_sas_url)[1]
  sunbird_container_url = "https://${var.sunbird_public_artifacts_account}.blob.core.windows.net/${var.sunbird_public_artifacts_container}?${local.sas_query}"
}

resource "null_resource" "copy_from_sunbird_container" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = <<EOT
      AZCOPY_AUTO_LOGIN_TYPE=AZCLI azcopy copy \
        "${local.sunbird_container_url}" \
        "https://${var.storage_account_name}.blob.core.windows.net/${var.storage_container_public}" \
        --recursive \
        --exclude-path ".terragrunt-source-manifest"
    EOT
  }
}

resource "local_file" "output_files" {
  for_each = toset(local.template_files)
  content  = templatefile("${path.module}/sunbird-rc/schemas/${each.value}", {
     cloud_storage_schema_url = "https://${var.storage_account_name}.blob.core.windows.net/${var.storage_container_public}"
  })
  filename = "${path.module}/sunbird-rc/schemas/${each.value}"
}

resource "null_resource" "upload_rc_schemas_to_public_blob" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "az storage blob upload-batch --account-name ${var.storage_account_name} --destination ${var.storage_container_public}/schemas --source ${path.module}/sunbird-rc/schemas --auth-mode login --overwrite"
  }
  depends_on = [local_file.output_files]
}
