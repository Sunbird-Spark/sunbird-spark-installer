include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/network.hcl"
}

locals {
  global_vars = yamldecode(file(find_in_parent_folders("global-values.yaml")))
}

skip = local.global_vars.global.skip_network_module
