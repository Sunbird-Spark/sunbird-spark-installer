include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/vm.hcl"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    runner_subnet_id = "mock-runner-subnet-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  runner_subnet_id = dependency.network.outputs.runner_subnet_id
}
