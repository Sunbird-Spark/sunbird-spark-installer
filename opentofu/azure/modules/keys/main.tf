terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "tls" {}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

data "azurerm_client_config" "current" {}

locals {
  global_values_keys_file = "${var.base_location}/../global-keys-values.yaml"
  jwt_script_location = "${var.base_location}/../../../../scripts/jwt-keys.py"
  rsa_script_location = "${var.base_location}/../../../../scripts/rsa-keys.py"
  global_values_jwt_file_location = "${var.base_location}/../../../../scripts/global-values-jwt-tokens.yaml"
  global_values_rsa_file_location = "${var.base_location}/../../../../scripts/global-values-rsa-keys.yaml"
  global_values_file = "${var.base_location}/../global-values.yaml"

  environment_name = "${var.building_block}-${var.environment}"
  common_tags = {
    environment   = var.environment
    BuildingBlock = var.building_block
  }
}
resource "random_password" "generated_string" {
  length  = 16          # Length of the string (can be between 12 and 24)
  special = false        # Do not include special characters
  upper   = true         # Include uppercase letters
  lower   = true         # Include lowercase letters
  numeric = true         # Include numbers
}

resource "null_resource" "generate_jwt_keys" {
  # Run ONCE at create. Do NOT use timestamp() triggers — that regenerates
  # keys on every `terragrunt apply` and breaks existing services that
  # validate JWTs against the prior keys.
  # To force key regeneration: uncomment the triggers block below, run terragrunt apply,
  # then re-comment to prevent regeneration on future runs.
  # triggers = {
  #   script_hash = filemd5(local.jwt_script_location)
  # }
  provisioner "local-exec" {
    command = <<EOT
      python3 ${local.jwt_script_location} ${random_password.generated_string.result} && \
      yq eval-all 'select(fileIndex == 0) *+ {"global": (select(fileIndex == 0).global * load("${local.global_values_jwt_file_location}"))}' -i ${var.base_location}/../global-values.yaml

    EOT
  }
}


resource "null_resource" "generate_rsa_keys" {
  # Run ONCE at create. See note on generate_jwt_keys above.
  provisioner "local-exec" {
    command = <<EOT
      python3 ${local.rsa_script_location} ${var.rsa_keys_count} && \
      yq eval-all 'select(fileIndex == 0) *+ {"global": (select(fileIndex == 0).global * load("${local.global_values_rsa_file_location}"))}' -i ${var.base_location}/../global-values.yaml
    EOT
  }
}

resource "null_resource" "upload_global_jwt_values_yaml" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = <<EOT
      [ -f ${local.global_values_jwt_file_location} ] || python3 ${local.jwt_script_location} ${random_password.generated_string.result}
      az storage blob upload --account-name ${var.storage_account_name} --container-name ${var.storage_container_private} --name ${var.environment}-global-values-jwt-tokens.yaml --file ${local.global_values_jwt_file_location} --auth-mode login --overwrite
    EOT
  }
  depends_on = [ null_resource.generate_jwt_keys ]
}

resource "null_resource" "upload_global_rsa_values_yaml" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = <<EOT
      [ -f ${local.global_values_rsa_file_location} ] || python3 ${local.rsa_script_location} ${var.rsa_keys_count}
      az storage blob upload --account-name ${var.storage_account_name} --container-name ${var.storage_container_private} --name ${var.environment}-global-values-rsa-keys.yaml --file ${local.global_values_rsa_file_location} --auth-mode login --overwrite
    EOT
  }
  depends_on = [ null_resource.generate_rsa_keys ]
}

# Sample code to enable encryption of global values files
# Encrypted files cannot be passed to helm

# resource "null_resource" "terrahelp_encryption" {
#   triggers = {
#     command = "${timestamp()}"
#   }
#   provisioner "local-exec" {
#       command = "terrahelp encrypt -simple-key=${random_password.generated_string.result} } -file=${local.global_values_keys_file}"
#   }
# }

# ---------------------------------------------------------------------------
# Key Vault — mirrors the JWT/RSA secrets this module generates (and the
# random_passwords module's admin passwords) into a real secrets manager,
# in addition to the existing plaintext global-values.yaml / blob-upload
# path above. This is deliberately additive, not a replacement: charts still
# read these values from global-values.yaml today, so the plaintext path
# has to keep working until a later phase moves chart consumption over to
# Key Vault (e.g. via the Secrets Store CSI driver). What this buys now:
# rotation and Key Vault's own access audit log, independent of that
# migration.
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "vault" {
  name                = "${local.environment_name}-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  # Not purge-protected on purpose: install.sh's destroy_tf_resources runs
  # `tofu destroy`, which soft-deletes this vault. Purge protection would
  # keep the name reserved for the full soft-delete retention window (up to
  # 90 days) with no way to force it, so re-running create_tf_resources for
  # the same env name would fail on a name collision. Soft-delete alone
  # (default retention, can't be turned off in this provider version) still
  # protects against accidental deletes; `az keyvault purge` stays available
  # for an intentional same-name recreate.
  purge_protection_enabled = false

  # Selected-networks, not Private Link — matches the storage account's
  # firewall approach (network_rules in the storage module) rather than
  # adding a private endpoint + private DNS zone, which would be the even
  # more locked-down option but is a bigger dependency chain than this pass
  # covers. Revisit if that's ever worth the added complexity.
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.aks_subnet_id, var.runner_subnet_id]
  }

  tags = merge(local.common_tags, var.additional_tags)
}

# rbac_authorization_enabled means vault access policies don't apply — the
# identity running `apply` needs an explicit RBAC grant to write secrets.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Read back the same file generate_jwt_keys/generate_rsa_keys just merged
# the JWT tokens and RSA keypairs into, so their values can be mirrored into
# Key Vault as real Terraform-managed secrets instead of only living in this
# plaintext YAML.
data "local_file" "global_values_after_keys" {
  filename = local.global_values_file

  depends_on = [
    null_resource.generate_jwt_keys,
    null_resource.generate_rsa_keys,
  ]
}

locals {
  generated_global = yamldecode(data.local_file.global_values_after_keys.content).global

  # Everything this module generates is shaped either "<consumer>_jwt"
  # (a token string) or "<prefix>_private_keys" / "<prefix>_public_keys" (a
  # map of key-name -> PEM string, from rsa-keys.py) — match on shape rather
  # than an exact list so this doesn't silently go stale if rsa-keys.py's
  # prefix list or jwt-keys.py's consumer list ever changes.
  generated_secret_source_keys = [
    for k, v in local.generated_global : k
    if can(regex("(_jwt|_private_keys|_public_keys)$", k))
  ]

  # Key Vault secret names allow only alphanumerics and dashes.
  # Maps (the RSA keypair fields) get JSON-encoded — Key Vault secrets are
  # strings only; scalars (JWT tokens) are stored as-is.
  generated_secrets = {
    for k in local.generated_secret_source_keys :
    replace(k, "_", "-") => (
      can(tomap(local.generated_global[k]))
      ? jsonencode(local.generated_global[k])
      : tostring(local.generated_global[k])
    )
  }

  # random_passwords module outputs — clean typed values already, no
  # read-back needed.
  password_secrets = {
    "grafana-admin-password"  = var.grafana_admin_password
    "superset-admin-password" = var.superset_admin_password
    "keycloak-password"       = var.keycloak_password
  }

  all_generated_secrets = merge(local.generated_secrets, local.password_secrets)
}

resource "azurerm_key_vault_secret" "generated" {
  for_each = local.all_generated_secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.vault.id

  # RBAC role assignments can take a short while to propagate — without
  # this the very first apply can 403 writing secrets right after the vault
  # and role assignment are created.
  depends_on = [azurerm_role_assignment.deployer_secrets_officer]
}


