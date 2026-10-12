terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  features {}
  resource_provider_registrations = "none"
}

locals {
  common_tags = {
    environment   = "${var.environment}"
    BuildingBlock = "${var.building_block}"
  }
  environment_name = "${var.building_block}-${var.environment}"
}

# Added: CSPM "Defender for X should be enabled" + "Security center pricing should be set
# to standard" findings -- subscription-wide threat-detection add-ons (monitoring only,
# no effect on how any resource runs or serves traffic).
resource "azurerm_security_center_subscription_pricing" "defender" {
  for_each      = toset(var.defender_resource_types)
  tier          = "Standard"
  resource_type = each.value
}

# Added: destination for the subscription Activity Log below. Separate from the AKS
# control-plane log workspace in modules/aks -- this one is subscription-scoped, not
# tied to a single cluster.
resource "azurerm_log_analytics_workspace" "activity_logs" {
  name                = "${local.environment_name}-activity-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags = merge(
    local.common_tags,
    var.additional_tags
  )
}

# Added: CSPM "Azure subscriptions should have a log profile for Activity Log" + "Ensure a
# 'Diagnostic Setting' exists for Subscription Activity Logs" -- routes who-changed-what
# subscription audit trail to Log Analytics; visibility only, no functional impact.
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "${local.environment_name}-activity-log"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.activity_logs.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }

  enabled_log {
    category = "Policy"
  }

  enabled_log {
    category = "Alert"
  }
}
