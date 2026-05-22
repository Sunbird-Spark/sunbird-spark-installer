provider "tls" {}

locals {
  global_values_keys_file = "${var.base_location}/../global-keys-values.yaml"
  jwt_script_location = "${var.base_location}/../../../../scripts/jwt-keys.py"
  rsa_script_location = "${var.base_location}/../../../../scripts/rsa-keys.py"
  global_values_jwt_file_location = "${var.base_location}/../../../../scripts/global-values-jwt-tokens.yaml"
  global_values_rsa_file_location = "${var.base_location}/../../../../scripts/global-values-rsa-keys.yaml"
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
  # validate JWTs against the prior keys. To force regeneration: `terraform taint`
  # this resource explicitly.
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


