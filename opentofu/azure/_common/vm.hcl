locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  subscription_id     = local.global_vars.global.subscription_id
  location            = local.global_vars.global.cloud_storage_region
  resource_group_name = get_env("AZURE_OPENTOFU_BACKEND_RG")

  vm_size             = try(local.global_vars.global.vm_size, "Standard_B2s")
  vm_admin_username   = try(local.global_vars.global.vm_admin_username, "azureuser")
  github_runner_token = local.global_vars.global.github_runner_token
  github_org          = local.global_vars.global.github_org
  github_repo         = try(local.global_vars.global.github_repo, "")
  pritunl_vpn_network = try(local.global_vars.global.pritunl_vpn_network, "172.16.0.0/24")
  pritunl_org_name    = try(local.global_vars.global.pritunl_org_name, "sunbird-spark")
  pritunl_users       = try(local.global_vars.global.pritunl_users, [])
}

terraform {
  source = "../../modules//vm/"
}

inputs = {
  environment         = local.environment
  building_block      = local.building_block
  subscription_id     = local.subscription_id
  location            = local.location
  resource_group_name = local.resource_group_name
  vm_size             = local.vm_size
  vm_admin_username   = local.vm_admin_username
  github_runner_token = local.github_runner_token
  github_org          = local.github_org
  github_repo         = local.github_repo
  pritunl_vpn_network = local.pritunl_vpn_network
  pritunl_org_name    = local.pritunl_org_name
  pritunl_users       = local.pritunl_users
}
