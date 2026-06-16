include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/eks.hcl"
}

inputs = {
  subnet_ids = ["subnet-0bd6d2daa3e836679", "subnet-0bbeb8df17d354df1"]  # private subnets ap-south-1a, ap-south-1b
  additional_tags = {
    project     = "knowledge engine"
    country     = "india"
    environment = "dev"
    name        = "sanketika"
  }
}
