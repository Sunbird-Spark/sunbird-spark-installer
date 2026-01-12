generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
tofu {
  backend "gcs" {
    bucket  = "${get_env("OPENTOFU_BACKEND_BUCKET")}"
    prefix  = "${path_relative_to_include()}/tofu.tfstate"
  }
}
EOF
}
