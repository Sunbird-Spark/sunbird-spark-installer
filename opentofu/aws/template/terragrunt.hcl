generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
  terraform {
  backend "s3" {
    bucket         = "${get_env("AWS_OPENTOFU_BACKEND_BUCKET")}"
    key            = "${path_relative_to_include()}/tofu.tfstate"
    region         = "${get_env("AWS_OPENTOFU_BACKEND_REGION")}"
    dynamodb_table = "${get_env("AWS_OPENTOFU_BACKEND_DYNAMODB_TABLE")}"
    encrypt        = true
  }
}
EOF
}
