include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/workload-identity.hcl"
}

inputs = {
  additional_tags = {
    project     = "knowledge engine"
    country     = "india"
    environment = "dev"
    name        = "sanketika"
  }
}
