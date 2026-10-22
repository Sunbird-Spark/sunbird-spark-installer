include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/eks.hcl"
}

# module specific inputs
# inputs = {
#   var1 = "value1"
#   var2 = "value2"
# }
