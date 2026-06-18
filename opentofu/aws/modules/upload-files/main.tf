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
  public_artifacts_path = var.public_artifacts_path
}

resource "null_resource" "upload_public_artifacts" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = <<EOT
      aws s3 sync \
        "${local.public_artifacts_path}/installation" \
        s3://${var.s3_bucket_public}/installation/ \
        --region ${var.aws_region}
    EOT
  }
}

# clone_and_upload_content_plugins, build_and_upload_content_editor,
# build_and_upload_generic_editor, build_and_upload_content_player — not required for knowledge engine, disabled.

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
      aws s3 sync \
        "$tmpdir/knowledge-platform/schemas" \
        s3://${var.s3_bucket_public}/schemas/local/ \
        --region ${var.aws_region}
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
}

resource "local_file" "output_files" {
  for_each = toset(local.template_files)
  content  = templatefile("${path.module}/sunbird-rc/schemas/${each.value}", {
     cloud_storage_schema_url = "https://${var.s3_bucket_public}.s3.${var.aws_region}.amazonaws.com"
  })
  filename = "${path.module}/sunbird-rc/schemas/${each.value}"
}

resource "null_resource" "upload_rc_schemas_to_public_bucket" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "aws s3 sync ${path.module}/sunbird-rc/schemas s3://${var.s3_bucket_public}/schemas/ --region ${var.aws_region}"
  }
  depends_on = [local_file.output_files]
}
