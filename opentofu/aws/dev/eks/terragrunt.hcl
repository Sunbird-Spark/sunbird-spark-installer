include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/eks.hcl"
}

inputs = {
  big_node_count          = 2
  eks_public_access_cidrs = []
  additional_tags = {
    project     = "knowledge engine"
    country     = "india"
    environment = "dev"
    name        = "sanketika"
  }
}
