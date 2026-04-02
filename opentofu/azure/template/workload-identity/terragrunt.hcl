include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/workload-identity.hcl"
}

# Override namespace/SA name if needed
# inputs = {
#   k8s_namespace            = "custom-namespace"
#   k8s_service_account_name = "custom-sa-name"
# }
