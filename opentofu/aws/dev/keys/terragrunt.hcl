include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/keys.hcl"
}

skip = true  # Keys module not required for this deployment

# module specific inputs
inputs = {
  base_location = get_terragrunt_dir()
}
