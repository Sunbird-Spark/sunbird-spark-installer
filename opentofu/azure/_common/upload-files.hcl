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

inputs = {
  storage_account_name            = dependency.storage.outputs.azurerm_storage_account_name
  storage_container_public        = dependency.storage.outputs.azurerm_storage_container_public
}
