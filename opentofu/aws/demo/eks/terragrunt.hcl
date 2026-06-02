include "root" {
  path = find_in_parent_folders()
}

include "common" {
  path = "../../_common/eks.hcl"
}
