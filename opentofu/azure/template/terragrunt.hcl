generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
tofu {
  backend "azurerm" {
    resource_group_name  = "${get_env("AZURE_OPENTOFU_BACKEND_RG")}"
    storage_account_name = "${get_env("AZURE_OPENTOFU_BACKEND_STORAGE_ACCOUNT")}"
    container_name       = "${get_env("AZURE_OPENTOFU_BACKEND_CONTAINER")}"
    key                  = "${path_relative_to_include()}/tofu.tfstate"
  }
}
EOF
}