locals {
  global_vars = yamldecode(file(find_in_parent_folders("global-values.yaml")))
}

include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/storage.hcl"
}

skip = local.global_vars.global.skip_storage_module

inputs = {
  additional_tags = {
    project     = "knowledge engine"
    country     = "india"
    environment = "dev"
    name        = "sanketika"
  }
}
