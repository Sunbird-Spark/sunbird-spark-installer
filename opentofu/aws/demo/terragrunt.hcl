generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TERRAFORM_BACKEND_BUCKET")}"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "${get_env("AWS_REGION")}"
  }
}
EOF
}
