terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  template_files        = fileset("${path.module}/sunbird-rc/schemas", "*.json")
  public_artifacts_path = var.public_artifacts_path
}

resource "null_resource" "upload_public_artifacts" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      gsutil -m cp -r "${local.public_artifacts_path}/*" "gs://${var.storage_container_public}/"
    EOT
  }
}

resource "null_resource" "clone_and_upload_knowledge_platform_schemas" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT
      git clone --depth 1 --branch ${var.knowledge_platform_ref} https://github.com/Sunbird-Knowlg/knowledge-platform.git "$tmpdir/knowledge-platform"
      gsutil -m cp -r "$tmpdir/knowledge-platform/schemas/*" "gs://${var.storage_container_public}/schemas/local/"
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
}

resource "local_file" "output_files" {
  for_each = toset(local.template_files)
  content = templatefile("${path.module}/sunbird-rc/schemas/${each.value}", {
    cloud_storage_schema_url = "https://${var.storage_account_name}/${var.storage_container_public}"
  })
  filename = "${path.module}/sunbird-rc/schemas/${each.value}"
}

resource "null_resource" "upload_rc_schemas_to_public_blob" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "gsutil -m cp -r ${path.module}/sunbird-rc/schemas/* gs://${var.storage_container_public}/schemas/"
  }

  depends_on = [local_file.output_files]
}
