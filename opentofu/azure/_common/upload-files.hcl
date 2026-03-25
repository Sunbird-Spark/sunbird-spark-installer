terraform {
  source = "../../modules//upload-files/"
}

dependency "storage" {
    config_path = "../storage"
    mock_outputs = {
      azurerm_storage_account_name = "dummy-account"
      azurerm_storage_container_public = "dummy-container-public"
    }
}

dependency "workload_identity" {
    config_path = "../workload-identity"
    mock_outputs = {
      client_id = "00000000-0000-0000-0000-000000000000"
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
}

inputs = {
  storage_account_name            = dependency.storage.outputs.azurerm_storage_account_name
  storage_container_public        = dependency.storage.outputs.azurerm_storage_container_public
  managed_identity_client_id      = dependency.workload_identity.outputs.client_id
  tenant_id                       = dependency.workload_identity.outputs.tenant_id
}