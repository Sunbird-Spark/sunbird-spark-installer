locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "dummy", public_container_name: "dummy", private_container_name: "dummy", velero_storage_container_private: "dummy"}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  subscription_id     = local.global_vars.global.subscription_id
  location            = local.global_vars.global.cloud_storage_region

  # ai_pipeline_enabled is root-level (not nested under global:) — see opentofu/azure/template/
  # global-values.yaml. ai-pipeline's own namespace is created ad-hoc by install.sh (kubectl
  # create namespace), not by this module's kubernetes_namespace resource, so it's deliberately
  # excluded from k8s_namespaces below regardless of this flag — adding it there would make
  # Terraform try to create a namespace that may already exist and fail.
  ai_pipeline_enabled  = tostring(try(local.global_vars.ai_pipeline_enabled, "false")) == "true"
  base_service_accounts = {
    sunbird = {
      namespace = "sunbird"
      name      = "azure-managed-identity-sa"
    }
    velero = {
      namespace = "velero"
      name      = "azure-managed-identity-sa"
    }
  }
  service_accounts = local.ai_pipeline_enabled ? merge(local.base_service_accounts, {
    "ai-pipeline" = {
      namespace = "ai-pipeline"
      name      = "azure-managed-identity-sa"
    }
  }) : local.base_service_accounts
}

terraform {
  source = "../../modules//workload-identity/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    resource_group_name = "dummy-rg"
  }
}

dependency "aks" {
  config_path = "../aks"
  mock_outputs = {
    oidc_issuer_url        = "https://dummy-oidc.eastus.cloudapp.azure.com/"
    kubernetes_host        = "https://dummy.hcp.eastus.azmk8s.io:443"
    client_certificate     = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
    client_key             = "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVkt..."
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
  }
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    azurerm_storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dummy-rg/providers/Microsoft.Storage/storageAccounts/dummy"
    azurerm_storage_container_public    = "dummy-public"
    azurerm_storage_container_private   = "dummy-private"
    azurerm_velero_container_name       = "dummy-velero"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  subscription_id                    = local.subscription_id
  location                           = local.location
  resource_group_name                = dependency.network.outputs.resource_group_name
  oidc_issuer_url                    = dependency.aks.outputs.oidc_issuer_url
  storage_account_id                 = local.skip_storage_module ? "/subscriptions/${local.subscription_id}/resourceGroups/${dependency.network.outputs.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${local.cloud_vars.global.cloud_storage_access_key}" : dependency.storage.outputs.azurerm_storage_account_resource_id
  kubernetes_host                    = dependency.aks.outputs.kubernetes_host
  kubernetes_client_certificate      = dependency.aks.outputs.client_certificate
  kubernetes_client_key              = dependency.aks.outputs.client_key
  kubernetes_cluster_ca_certificate  = dependency.aks.outputs.cluster_ca_certificate
  k8s_service_accounts               = local.service_accounts
}
