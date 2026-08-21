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

resource "null_resource" "clone_and_upload_content_plugins" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT
      git clone --depth 1 --branch ${var.sunbird_player_editor_ref} https://github.com/Sunbird-Knowlg/sunbird-content-plugins.git "$tmpdir/content-plugins"
      gsutil -m cp -r "$tmpdir/content-plugins/*" "gs://${var.storage_container_public}/content-plugins/"
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
}

resource "null_resource" "build_and_upload_content_editor" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      git clone --depth 1 --branch ${var.sunbird_player_editor_ref} https://github.com/Sunbird-Knowlg/sunbird-content-editor.git "$tmpdir/content-editor"

      host_uid=$(id -u)
      host_gid=$(id -g)
      build_sha=$(git -C "$tmpdir/content-editor" rev-parse HEAD)

      docker run --rm \
        -e HOST_UID=$host_uid \
        -e HOST_GID=$host_gid \
        -e editorType=contentEditor \
        -e framework_version_number=${var.sunbird_player_editor_ref} \
        -e editor_version_number=${var.sunbird_player_editor_ref} \
        -e build_number=$build_sha \
        -e CHROME_BIN=google-chrome \
        -v "$tmpdir/content-editor":/work \
        -w /work \
        node:10.24.1-buster \
        bash -c '
          set -e
          sed -i "s|deb.debian.org/debian|archive.debian.org/debian|g; s|security.debian.org/debian-security|archive.debian.org/debian-security|g; /buster-updates/d" /etc/apt/sources.list
          apt-get -o Acquire::Check-Valid-Until=false update
          apt-get install -y build-essential libpng-dev git
          npm install -g bower@1.8.14 gulp@4.0.1
          git clone https://github.com/project-sunbird/sunbird-content-plugins.git plugins -b ${var.sunbird_player_editor_ref}
          npm cache clean --force
          npm install
          cd app
          bower cache clean --allow-root
          bower prune -f --allow-root
          bower install --force -V --allow-root
          cd ..
          npm install gulp-gzip --save-dev
          npm run build-npm-pkg
          chown -R $HOST_UID:$HOST_GID /work
        '

      gsutil -m cp -r "$tmpdir/content-editor/content-editor/*" "gs://${var.storage_container_public}/content-editor/"
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
}

resource "null_resource" "build_and_upload_generic_editor" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      git clone --depth 1 --branch ${var.sunbird_player_editor_ref} https://github.com/Sunbird-Knowlg/sunbird-generic-editor.git "$tmpdir/generic-editor"

      host_uid=$(id -u)
      host_gid=$(id -g)
      build_sha=$(git -C "$tmpdir/generic-editor" rev-parse HEAD)

      docker run --rm \
        -e HOST_UID=$host_uid \
        -e HOST_GID=$host_gid \
        -e version_number=${var.sunbird_player_editor_ref} \
        -e build_number=$build_sha \
        -v "$tmpdir/generic-editor":/work \
        -w /work \
        node:18.20.8-bullseye \
        bash -c '
          set -e
          apt-get update
          apt-get install -y build-essential libpng-dev git
          npm install -g bower@1.8.0
          git clone https://github.com/project-sunbird/sunbird-content-plugins.git plugins -b ${var.sunbird_player_editor_ref}
          npm install --legacy-peer-deps
          cd app
          bower cache clean --allow-root
          bower install --force --allow-root
          cd ..
          npm run build-npm-pkg
          chown -R $HOST_UID:$HOST_GID /work
        '

      gsutil -m cp -r "$tmpdir/generic-editor/generic-editor/*" "gs://${var.storage_container_public}/generic-editor/"
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
}

resource "null_resource" "build_and_upload_content_player" {
  triggers = {
    command = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      git clone --depth 1 --branch ${var.sunbird_player_editor_ref} https://github.com/Sunbird-Knowlg/sunbird-content-player.git "$tmpdir/content-player"

      host_uid=$(id -u)
      host_gid=$(id -g)

      docker run --rm \
        -e HOST_UID=$host_uid \
        -e HOST_GID=$host_gid \
        -v "$tmpdir/content-player":/work \
        -w /work \
        node:10.16.3-stretch \
        bash -c '
          set -e
          sed -i "s|deb.debian.org/debian|archive.debian.org/debian|g; s|security.debian.org/debian-security|archive.debian.org/debian-security|g; /stretch-updates/d" /etc/apt/sources.list
          apt-get -o Acquire::Check-Valid-Until=false update
          apt-get install -y python git build-essential
          ln -sf /usr/bin/python /usr/bin/python2
          npm config set python /usr/bin/python2
          git config --global url."https://".insteadOf git://
          cd player
          npm install --legacy-peer-deps
          npm run build-preview ekstep
          npm run build-npm-package
          chown -R $HOST_UID:$HOST_GID /work
        '

      gsutil -m cp -r "$tmpdir/content-player/player/www/*" "gs://${var.storage_container_public}/v3/"
    EOT
  }

  depends_on = [null_resource.upload_public_artifacts]
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
