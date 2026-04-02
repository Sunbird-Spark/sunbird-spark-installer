# Skipped: passwords are provided manually in global-values.yaml
# Uncomment below to re-enable auto password generation
# include "root" {
#   path = find_in_parent_folders("terragrunt.hcl")
# }
#
# include "environment" {
#   path = "${get_terragrunt_dir()}/../../_common/random_passwords.hcl"
# }

skip = true
