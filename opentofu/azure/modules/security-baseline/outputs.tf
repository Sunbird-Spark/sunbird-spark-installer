output "activity_log_workspace_id" {
  value = try(azurerm_log_analytics_workspace.activity_logs[0].id, null)
}
